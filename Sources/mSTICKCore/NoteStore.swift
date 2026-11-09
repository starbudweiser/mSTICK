import Combine
import Foundation

public enum NoteFilter: String, CaseIterable, Sendable { case all, active, archived }

/// Les notes en mémoire, enregistrées dans le coffre 250 ms après la dernière modification, synchronisées et recopiées en Markdown si demandé.
@MainActor
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [Note] = []
    public let vault: Vault
    public var syncFolder: URL? { didSet { if syncFolder != nil { scheduleSync(after: 0.5) } } }
    public var markdownFolder: URL? { didSet { if markdownFolder != nil { scheduleMirror() } } }
    /// Texte de repli pour les notes sans titre (langue de l'appli).
    public var untitled = "note"
    /// Appelée quand la synchro a remplacé ou supprimé des notes.
    public var onExternalChange: (([UUID]) -> Void)?
    public private(set) var lastSyncError: String?

    private var deleted: [UUID: Date] = [:]
    private var dirty = Set<UUID>()
    private var saveItem: DispatchWorkItem?
    private var syncItem: DispatchWorkItem?
    private var mirrorItem: DispatchWorkItem?
    private var syncing = false
    private var timer: Timer?

    public init(vault: Vault) {
        self.vault = vault
        let loaded = vault.loadAll()
        notes = loaded.notes
        deleted = loaded.deleted
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync(after: 0) }
        }
    }

    // MARK: Lecture

    public func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    /// Ordre du deck : épinglées d'abord, puis par rang.
    public var active: [Note] { sorted(notes.filter { !$0.archived }) }
    public var archived: [Note] { notes.filter(\.archived).sorted { $0.updatedAt > $1.updatedAt } }
    private func sorted(_ list: [Note]) -> [Note] {
        list.sorted { ($0.pinned ? 0 : 1, $0.order, $1.updatedAt) < ($1.pinned ? 0 : 1, $1.order, $0.updatedAt) }
    }

    public func search(_ query: String, filter: NoteFilter) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = notes.filter { filter == .all || (filter == .archived) == $0.archived }
        let hits = q.isEmpty ? pool : pool.filter { ($0.title + "\n" + $0.body + "\n" + $0.emoji).lowercased().contains(q) }
        return hits.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Modifications

    @discardableResult
    public func create(color: String = "yellow") -> Note {
        let order = (notes.map(\.order).min() ?? 1) - 1
        let note = Note(color: color, order: order)
        notes.append(note)
        touch(note.id)
        return note
    }

    public func update(_ id: UUID, touching: Bool = true, _ change: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var copy = notes[i]
        change(&copy)
        guard copy != notes[i] else { return }
        if touching { copy.updatedAt = Date() }
        notes[i] = copy
        touch(id)
    }

    public func setArchived(_ ids: [UUID], _ flag: Bool) {
        for id in ids { update(id) { $0.archived = flag; if flag { $0.pinned = false } } }
    }

    /// Supprime des notes et rend leurs copies (pour « Annuler »).
    @discardableResult
    public func delete(_ ids: [UUID]) -> [Note] {
        let gone = notes.filter { ids.contains($0.id) }
        let now = Date()
        notes.removeAll { ids.contains($0.id) }
        for note in gone {
            dirty.remove(note.id)
            deleted[note.id] = now
            try? vault.delete(note.id, at: now)
        }
        scheduleSync(after: 1); scheduleMirror()
        return gone
    }

    public func restore(_ gone: [Note]) {
        for var note in gone {
            deleted[note.id] = nil
            vault.forgetTombstone(note.id)
            note.updatedAt = Date()
            notes.append(note)
            touch(note.id)
        }
    }

    public func move(_ id: UUID, before other: UUID?) {
        var list = active.filter { $0.id != id }
        guard let note = note(id) else { return }
        let index = other.flatMap { o in list.firstIndex { $0.id == o } } ?? list.count
        list.insert(note, at: index)
        for (rank, n) in list.enumerated() { update(n.id, touching: false) { $0.order = rank } }
    }

    private func touch(_ id: UUID) {
        dirty.insert(id)
        saveItem?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flush() } }
        saveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    /// Écrit tout de suite ce qui est en attente (quitter l'appli, changement de dossier).
    public func flush() {
        saveItem?.cancel()
        let pending = dirty
        dirty = []
        for id in pending { if let n = note(id) { try? vault.save(n) } }
        if !pending.isEmpty { scheduleSync(after: 2); scheduleMirror() }
    }

    // MARK: Import

    @discardableResult
    public func importArchive(_ data: Data) throws -> Int {
        let incoming = try Exporter.importArchive(data)
        var added = 0
        for note in incoming where self.note(note.id) == nil {
            deleted[note.id] = nil; vault.forgetTombstone(note.id)
            notes.append(note); touch(note.id); added += 1
        }
        return added
    }

    // MARK: Synchro et copie Markdown

    public func scheduleSync(after delay: TimeInterval) {
        guard syncFolder != nil else { return }
        syncItem?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.syncNow() } }
        syncItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func syncNow() {
        guard let folder = syncFolder, !syncing else { return }
        flush()
        syncing = true
        let snapshot = notes, tombs = deleted
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try SyncEngine.run(folder: folder, notes: snapshot, deleted: tombs) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finishSync(result) } }
        }
    }

    private func finishSync(_ result: Result<SyncEngine.Outcome, Error>) {
        syncing = false
        switch result {
        case .failure(let error): lastSyncError = error.localizedDescription
        case .success(let outcome):
            lastSyncError = nil
            var changed: [UUID] = []
            for note in outcome.updates {
                if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = note } else { notes.append(note) }
                deleted[note.id] = nil; vault.forgetTombstone(note.id)
                try? vault.save(note); changed.append(note.id)
            }
            for id in outcome.removals {
                notes.removeAll { $0.id == id }
                deleted[id] = deleted[id] ?? Date()
                try? vault.delete(id, at: deleted[id]!); changed.append(id)
            }
            if !changed.isEmpty { onExternalChange?(changed); scheduleMirror() }
        }
    }

    private func scheduleMirror() {
        guard markdownFolder != nil else { return }
        mirrorItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let folder = self.markdownFolder else { return }
                let snapshot = self.notes, fallback = self.untitled
                DispatchQueue.global(qos: .utility).async { try? Exporter.mirror(snapshot, to: folder, fallback: fallback) }
            }
        }
        mirrorItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}

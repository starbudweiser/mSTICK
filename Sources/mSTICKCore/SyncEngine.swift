import Foundation

/// Synchronisation par dossier (iCloud Drive par défaut) : un fichier `<id>.hmnote` par note (JSON), un marqueur
/// `<id>.hmdeleted` par note effacée. La version la plus récente gagne ; un effacement plus récent que la note l'emporte.
public enum SyncEngine {
    public struct Outcome {
        public var updates: [Note] = []      // notes à créer ou remplacer en local
        public var removals: [UUID] = []     // notes à effacer en local
        public var written = 0
    }

    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/mSTICK", isDirectory: true)
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .prettyPrinted]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private struct Marker: Codable { var deletedAt: Date }

    private static func seconds(_ d: Date) -> Int { Int(d.timeIntervalSince1970) }

    public static func run(folder: URL, notes: [Note], deleted: [UUID: Date]) throws -> Outcome {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var remote: [UUID: Note] = [:]
        var remoteDeleted: [UUID: Date] = [:]
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.lastPathComponent
            if name.hasSuffix(".icloud") { // fichier iCloud pas encore téléchargé : on le demande, il sera lu à la prochaine passe
                let real = String(name.dropFirst().dropLast(".icloud".count))
                try? fm.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(real))
                continue
            }
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), let data = try? Data(contentsOf: url) else { continue }
            if url.pathExtension == "hmnote", let note = try? decoder.decode(Note.self, from: data) { remote[id] = note }
            else if url.pathExtension == "hmdeleted", let m = try? decoder.decode(Marker.self, from: data) { remoteDeleted[id] = m.deletedAt }
        }

        var out = Outcome()
        func noteURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).hmnote") }
        func markerURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).hmdeleted") }
        let local = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

        for note in notes {
            if let gone = remoteDeleted[note.id], seconds(gone) >= seconds(note.updatedAt) { out.removals.append(note.id); continue }
            if let other = remote[note.id] {
                if seconds(other.updatedAt) > seconds(note.updatedAt) { out.updates.append(other) }
                else if seconds(other.updatedAt) < seconds(note.updatedAt) { try encoder.encode(note).write(to: noteURL(note.id), options: .atomic); out.written += 1 }
            } else {
                try encoder.encode(note).write(to: noteURL(note.id), options: .atomic); out.written += 1
            }
        }
        for (id, other) in remote where local[id] == nil {
            if let gone = deleted[id], seconds(gone) >= seconds(other.updatedAt) {
                try? fm.removeItem(at: noteURL(id))
                if remoteDeleted[id] == nil { try encoder.encode(Marker(deletedAt: gone)).write(to: markerURL(id), options: .atomic); out.written += 1 }
            } else if let gone = remoteDeleted[id], seconds(gone) >= seconds(other.updatedAt) {
                try? fm.removeItem(at: noteURL(id))
            } else {
                out.updates.append(other)
            }
        }
        for (id, date) in deleted where remoteDeleted[id] == nil && local[id] == nil {
            try encoder.encode(Marker(deletedAt: date)).write(to: markerURL(id), options: .atomic); out.written += 1
            if let other = remote[id], seconds(date) >= seconds(other.updatedAt) { try? fm.removeItem(at: noteURL(id)) }
        }
        return out
    }
}

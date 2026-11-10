import AppKit
import SwiftUI
import UniformTypeIdentifiers
import mSTICKCore

@MainActor
final class AllNotesModel: ObservableObject {
    @Published var query = ""
    @Published var filter: NoteFilter = .all
    @Published var selection = Set<UUID>()
    @Published var editing = false
}

/// « Toutes les notes » (⌥⌘L) et « Archive » (⌥⌘A) : recherche, filtres, sélection multiple, export, suppression.
struct AllNotesView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var model: AllNotesModel
    let open: (UUID) -> Void
    @State private var confirmDelete = false
    @State private var message: String?
    private let prefs = Prefs.shared

    private var results: [Note] { store.search(model.query, filter: model.filter) }
    private var chosen: [Note] { results.filter { model.selection.contains($0.id) } }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: Socle.M.space2) {
                    TextField(L("all.search"), text: $model.query).textFieldStyle(.plain).socleField()
                    Picker("", selection: $model.filter) {
                        Text(L("all.filter.all")).tag(NoteFilter.all)
                        Text(L("all.filter.active")).tag(NoteFilter.active)
                        Text(L("all.filter.archived")).tag(NoteFilter.archived)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                .padding(Socle.M.space3)
                List(selection: $model.selection) {
                    ForEach(results) { note in row(note).tag(note.id) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay { if results.isEmpty { Text(L(model.query.isEmpty ? "all.empty" : "all.nomatch")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted) } }
                Divider().overlay(Socle.C.border)
                footer
            }
            .frame(width: 320)
            .background(Socle.C.surfaceRaised)
            Divider().overlay(Socle.C.border)
            preview.frame(maxWidth: .infinity, maxHeight: .infinity).background(Socle.C.bg)
        }
        .alert(L("all.delete.title", chosen.count), isPresented: $confirmDelete) {
            Button(L("all.delete.confirm"), role: .destructive) { delete() }
            Button(L("all.cancel"), role: .cancel) {}
        } message: { Text(L("all.delete.message")) }
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: Socle.M.space2) {
            RoundedRectangle(cornerRadius: 2).fill(Color(noteColor: note.color)).frame(width: 5, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text([note.emoji, note.displayTitle(fallback: L("note.untitled"))].filter { !$0.isEmpty }.joined(separator: " "))
                    .socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                HStack(spacing: 6) {
                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                    if note.archived { Text(L("all.filter.archived")).socle(Socle.T.meta).foregroundStyle(Socle.C.warning) }
                    if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Socle.C.textMuted) }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        // Double-clic en parallèle : un onTapGesture(count: 2) placé avant retient le simple clic ~0,5 s.
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(note.id) })
        .onTapGesture {
            // Le double-clic masquait le simple clic : on sélectionne nous-mêmes (⌘ ajoute ou retire, ⇧ ajoute).
            let mods = NSEvent.modifierFlags
            if mods.contains(.command) { if model.selection.contains(note.id) { model.selection.remove(note.id) } else { model.selection.insert(note.id) } }
            else if mods.contains(.shift) { model.selection.insert(note.id) }
            else { model.selection = [note.id] }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            HStack(spacing: Socle.M.space2) {
                Menu(L("all.export")) {
                    Button(L("export.markdown")) { export(.markdown) }
                    Button(L("export.text")) { export(.text) }
                    Button(L("export.single")) { export(.single) }
                    Button(L("export.archive")) { export(.archive) }
                }
                .menuStyle(.button).buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                .disabled(chosen.isEmpty && results.isEmpty)
                Button(L("all.import")) { importArchive() }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                Spacer()
                Button(L("all.delete")) { confirmDelete = true }.buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize().disabled(chosen.isEmpty)
            }
            if let message { Text(message).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(2) }
            else { Text(L("all.count", results.count, chosen.count)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted) }
        }
        .padding(Socle.M.space3)
    }

    @ViewBuilder private var preview: some View {
        if chosen.count == 1, let note = chosen.first {
            VStack(alignment: .leading, spacing: Socle.M.space3) {
                HStack {
                    Text([note.emoji, note.displayTitle(fallback: L("note.untitled"))].filter { !$0.isEmpty }.joined(separator: " "))
                        .socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                    Spacer()
                    Picker("", selection: $model.editing) {
                        Text(L("all.mode.render")).tag(false)
                        Text(L("all.mode.edit")).tag(true)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    Button(L("all.open")) { open(note.id) }.buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                    Button(L(note.archived ? "note.unarchive" : "note.archive")) { store.setArchived([note.id], !note.archived) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
                Group {
                    if model.editing {
                        NoteEditor(text: note.body, family: note.font ?? (prefs.defaultFont.isEmpty ? nil : prefs.defaultFont), size: CGFloat(prefs.fontSize),
                                   tone: NSColor.labelColor, accent: NSColor.controlAccentColor, smartCalc: prefs.smartCalc, slash: prefs.slashCommands, reminders: false,
                                   onChange: { text in store.update(note.id) { $0.body = text } },
                                   onCancel: { model.editing = false }, onReminder: { _ in }, onCommand: { _ in }, ready: { _ in })
                            .id(note.id)
                    } else {
                        ScrollView { MarkdownPreview(text: note.body).socle(Socle.T.reading).foregroundStyle(Socle.C.text).textSelection(.enabled) }
                    }
                }
                .padding(Socle.M.space3).background(Socle.C.bgSunken).overlay(Rectangle().stroke(Socle.C.border))
            }
            .padding(Socle.M.space4)
        } else {
            Text(L(chosen.isEmpty ? "all.preview.none" : "all.preview.many", chosen.count)).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
        }
    }

    // MARK: Actions

    private func delete() {
        let gone = store.delete(chosen.map(\.id))
        model.selection = []
        Toast.show(L("toast.deleted.many", gone.count), action: L("toast.undo")) { store.restore(gone) }
    }

    private func export(_ format: ExportFormat) {
        let notes = chosen.isEmpty ? results : chosen
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = L("all.export.here")
        panel.message = L("all.export.message", notes.count)
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let files = try Exporter.export(notes, format: format, to: dir, fallback: L("note.untitled"))
            message = L("all.exported", files.count)
        } catch { message = error.localizedDescription }
    }

    private func importArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        if let t = UTType(filenameExtension: "stickies") { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = try store.importArchive(Data(contentsOf: url))
            message = L("all.imported", added)
        } catch { message = L("all.import.failed") }
    }
}

@MainActor
final class AllNotesWindow {
    private var window: NSWindow?
    let model = AllNotesModel()

    func show(store: NoteStore, filter: NoteFilter, open: @escaping (UUID) -> Void, quietly: Bool = false) {
        model.filter = filter
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 720, height: 420)
            w.setFrameAutosaveName("mSTICK.allNotes")
            w.contentView = NSHostingView(rootView: AllNotesView(store: store, model: model, open: open))
            window = w
            if !w.setFrameUsingName("mSTICK.allNotes") { w.center() }
        }
        window?.title = L(filter == .archived ? "all.title.archive" : "all.title")
        if quietly { window?.orderFront(nil) } else { window?.present() }
    }
}

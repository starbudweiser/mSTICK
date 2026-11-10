import AppKit
import SwiftUI
import mSTICKCore

enum NoteMetrics {
    /// Hauteur de la barre de titre : c'est aussi celle d'une note repliée dans une pile.
    static let titleHeight: CGFloat = 26
    static let corner: CGFloat = 12
}

@MainActor
final class NoteViewModel: ObservableObject {
    let id: UUID
    let store: NoteStore
    weak var editor: StickTextView?
    @Published var showFormat = false
    /// Rendu par défaut (sans balises) ; en édition, l'éditeur Markdown en direct.
    @Published var editing = false
    var focusPending = false
    @Published var hovering = false
    /// Dans une pile et pas la note ouverte : seule la barre de titre se voit.
    @Published var collapsed = false
    @Published var inStack = false
    var onClose: () -> Void = {}
    var onDelete: () -> Void = {}
    var onActivate: () -> Void = {}
    var onUnstack: () -> Void = {}
    var onRemoveFromStack: () -> Void = {}
    var onCloseStack: () -> Void = {}
    var onColorStack: (StackColoring) -> Void = { _ in }
    var onCommand: (String) -> Void = { _ in }
    init(id: UUID, store: NoteStore) { self.id = id; self.store = store }
}

enum StackColoring { case spectrum, unique, same }

private let fontChoices = ["Avenir Next", "Georgia", "Menlo", "Bradley Hand", "Noteworthy", "Marker Felt", "Chalkboard SE", "Inconsolata"]

/// Couleurs d'une note selon le thème : sombre (fond presque noir teinté, titre en couleur) ou clair (fond pastel).
struct NoteTheme {
    let dark: Bool
    let bg: Color
    let accent: Color
    let accentNS: NSColor
    let text: Color
    let textNS: NSColor

    init(color: String, dark: Bool) {
        self.dark = dark
        let hex = NoteColor.hex(color)
        if dark {
            bg = Color(noteColor: NoteColor.darkBackground(color))
            accent = Color(noteColor: hex); accentNS = NSColor(noteColor: hex)
            text = Color(white: 0.93); textNS = NSColor(white: 0.93, alpha: 1)
        } else {
            bg = Color(noteColor: hex)
            let deep = NoteColor.mix(hex, "#000000", 0.62)
            accent = Color(noteColor: deep); accentNS = NSColor(noteColor: deep)
            text = Color(white: 0.12); textNS = NSColor(white: 0.12, alpha: 1)
        }
    }
}

struct NoteView: View {
    @ObservedObject var vm: NoteViewModel
    @ObservedObject var store: NoteStore
    @ObservedObject var prefs = Prefs.shared
    @Environment(\.colorScheme) private var scheme
    @State private var options = false
    @State private var renaming = false
    @FocusState private var titleFocus: Bool

    private var note: Note { store.note(vm.id) ?? Note(id: vm.id) }
    private var theme: NoteTheme { NoteTheme(color: note.color, dark: scheme == .dark) }
    private var chromeVisible: Bool { vm.hovering || options }

    var body: some View {
        let t = theme
        VStack(spacing: 0) {
            titleBar(t)
            if !vm.collapsed {
                if vm.editing {
                    NoteEditor(text: note.body, family: note.font ?? (prefs.defaultFont.isEmpty ? nil : prefs.defaultFont), size: CGFloat(prefs.fontSize),
                               tone: t.textNS, accent: t.accentNS, smartCalc: prefs.smartCalc, slash: prefs.slashCommands, reminders: prefs.reminders,
                               onChange: { text in store.update(vm.id) { $0.body = text; if let r = $0.reminders { let keep = r.filter { text.contains($0.label) }; $0.reminders = keep.isEmpty ? nil : keep } } },
                               onCancel: { vm.onClose() },
                               onReminder: { reminder in store.update(vm.id) { $0.reminders = ($0.reminders ?? []) + [reminder] } },
                               onCommand: { vm.onCommand($0) },
                               ready: { ed in
                                   vm.editor = ed
                                   if vm.focusPending { vm.focusPending = false; DispatchQueue.main.async { ed.window?.makeFirstResponder(ed) } }
                               })
                } else {
                    ScrollView {
                        MarkdownPreview(text: note.body, size: CGFloat(prefs.fontSize), family: note.font ?? (prefs.defaultFont.isEmpty ? nil : prefs.defaultFont),
                                        strong: t.text, ink: t.text, muted: t.text.opacity(0.6), tint: t.accent, line: t.text.opacity(0.25))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { vm.focusPending = true; vm.editing = true }
                }
                if vm.editing && (vm.hovering || vm.showFormat) { toolbar(t) }
            }
        }
        .background(t.bg)
        .clipShape(RoundedRectangle(cornerRadius: NoteMetrics.corner))
        .overlay(RoundedRectangle(cornerRadius: NoteMetrics.corner).stroke(t.dark ? Color.white.opacity(0.09) : Color.black.opacity(0.12), lineWidth: 0.5))
        .onHover { vm.hovering = $0 }
    }

    // MARK: Barre de titre : croix, titre au centre, réglages

    private func titleBar(_ t: NoteTheme) -> some View {
        let title = note.displayTitle(fallback: L("note.untitled"))
        let empty = note.title.trimmingCharacters(in: .whitespaces).isEmpty && note.displayTitle(fallback: "") .isEmpty
        let closeButton = CloseButton(style: prefs.closeStyle, color: t.accent) { vm.onClose() }
        let gear = Button { options = true } label: {
            Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(t.accent.opacity(0.75)).frame(width: 22, height: NoteMetrics.titleHeight)
        }
        .buttonStyle(.plain).help(L("note.options"))
        .opacity(chromeVisible || vm.collapsed ? 1 : 0)
        .popover(isPresented: $options, arrowEdge: .bottom) { optionsView }
        let modeButton = Button { vm.focusPending = !vm.editing; vm.editing.toggle() } label: {
            Image(systemName: vm.editing ? "eye" : "pencil").font(.system(size: 10, weight: .bold)).foregroundStyle(t.accent.opacity(0.75)).frame(width: 22, height: NoteMetrics.titleHeight)
        }
        .buttonStyle(.plain).help(L(vm.editing ? "note.mode.render" : "note.mode.edit"))
        .opacity(chromeVisible && !vm.collapsed ? 1 : 0)
        return ZStack {
            Group {
                if renaming && !vm.collapsed {
                    TextField(L("note.title.placeholder"), text: Binding(get: { note.title }, set: { v in store.update(vm.id) { $0.title = v } }))
                        .textFieldStyle(.plain).multilineTextAlignment(.center).focused($titleFocus)
                        .onSubmit { renaming = false }
                        .onChange(of: titleFocus) { _, f in if !f { renaming = false } }
                        .onAppear { titleFocus = true }
                } else {
                    Text(title).lineLimit(1).opacity(empty ? 0.55 : 1)
                }
            }
            .font(.system(size: 11, weight: .semibold)).tracking(0.2).foregroundStyle(t.accent).padding(.horizontal, 54)
            HStack(spacing: 0) {
                if prefs.closeLeft { closeButton; Spacer(minLength: 0); modeButton; gear } else { gear; modeButton; Spacer(minLength: 0); closeButton }
            }
            .padding(.horizontal, 5)
        }
        .frame(height: NoteMetrics.titleHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if vm.collapsed { vm.onActivate() } else { renaming = true } }
        .onTapGesture { if vm.collapsed { vm.onActivate() } }
        .windowDrag()
    }

    // MARK: Barre d'outils (au survol)

    private func toolbar(_ t: NoteTheme) -> some View {
        HStack(spacing: 2) {
            Button { withAnimation(.easeOut(duration: 0.15)) { vm.showFormat.toggle() } } label: {
                Text("Aa").font(.system(size: 12, weight: .bold)).foregroundStyle(t.text).frame(width: 28, height: 22)
                    .background(vm.showFormat ? t.text.opacity(0.14) : .clear).clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain).help(L("note.format"))
            if vm.showFormat {
                formatButton(t, "bold", L("format.bold")) { vm.editor?.toggleWrap("**") }
                formatButton(t, "italic", L("format.italic")) { vm.editor?.toggleWrap("*") }
                formatButton(t, "underline", L("format.underline")) { vm.editor?.toggleWrap("<u>", "</u>") }
                formatButton(t, "strikethrough", L("format.strike")) { vm.editor?.toggleWrap("~~") }
                formatButton(t, "textformat.size", L("format.heading")) { vm.editor?.togglePrefix("# ") }
                formatButton(t, "list.bullet", L("format.bullets")) { vm.editor?.togglePrefix("- ") }
                formatButton(t, "list.number", L("format.numbers")) { vm.editor?.togglePrefix("1. ") }
                formatButton(t, "checkmark.square", L("format.checks")) { vm.editor?.togglePrefix("- [ ] ") }
                formatButton(t, "link", L("format.link")) { vm.editor?.insertLink() }
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(WindowDragArea())
    }

    private func formatButton(_ t: NoteTheme, _ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.text).frame(width: 24, height: 22)
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: Réglages de la note

    private func checkRow(_ key: String, _ symbol: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 16)
                Text(L(key)).socle(Socle.T.body)
                Spacer(minLength: 0)
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Socle.C.accent) }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("note.color")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 8), spacing: 6) {
                ForEach(prefs.allColors, id: \.self) { id in
                    Button { store.update(vm.id) { $0.color = id } } label: {
                        Circle().fill(Color(noteColor: id)).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(note.color == id ? Socle.C.accent : Color.black.opacity(0.25), lineWidth: note.color == id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L("note.font")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            Picker("", selection: Binding(get: { note.font ?? "" }, set: { f in store.update(vm.id) { $0.font = f.isEmpty ? nil : f } })) {
                Text(L("note.font.system")).tag("")
                ForEach(fontChoices.filter { NSFontManager.shared.availableFontFamilies.contains($0) }, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 190)
            Divider()
            checkRow("note.float", "square.stack.3d.up", note.pinned) { store.update(vm.id) { $0.pinned.toggle(); if $0.pinned { $0.glued = nil } } }
            checkRow("note.glue", "pin", note.glued == true) { store.update(vm.id) { $0.glued = ($0.glued == true) ? nil : true; if $0.glued == true { $0.pinned = false } } }
            checkRow("note.desktops", "rectangle.on.rectangle", note.allDesktops == true) { store.update(vm.id) { $0.allDesktops = ($0.allDesktops == true) ? nil : true } }
            if vm.inStack {
                Divider()
                Text(L("stack.title")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
                HStack(spacing: 6) {
                    Button(L("stack.spectrum")) { vm.onColorStack(.spectrum) }
                    Button(L("stack.unique")) { vm.onColorStack(.unique) }
                    Button(L("stack.same")) { vm.onColorStack(.same) }
                }.buttonStyle(.link).font(.system(size: 11))
                checkRow("stack.remove", "rectangle.badge.minus", false) { options = false; vm.onRemoveFromStack() }
                checkRow("stack.unstack", "rectangle.expand.vertical", false) { options = false; vm.onUnstack() }
                checkRow("stack.close", "xmark.rectangle", false) { options = false; vm.onCloseStack() }
            }
            Divider()
            Button { options = false; store.setArchived([vm.id], !note.archived); vm.onClose() } label: {
                Label(L(note.archived ? "note.unarchive" : "note.archive"), systemImage: note.archived ? "tray.and.arrow.up" : "archivebox").socle(Socle.T.body)
            }.buttonStyle(.plain)
            Button { options = false; vm.onDelete() } label: {
                Label(L("note.delete"), systemImage: "trash").socle(Socle.T.body).foregroundStyle(Socle.C.danger)
            }.buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 222, alignment: .leading)
    }
}

// MARK: Croix de fermeture

/// Dessin d'une des huit croix. `size` est le côté du dessin.
struct CloseGlyph: View {
    let style: CloseStyle
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Group {
            switch style {
            case .classic: Image(systemName: "xmark").font(.system(size: size, weight: .light))
            case .chunky: Image(systemName: "xmark").font(.system(size: size, weight: .black))
            case .hollow: Image(systemName: "xmark.square").font(.system(size: size + 1, weight: .regular))
            case .pixel: PixelCross().frame(width: size, height: size)
            case .crisscross: Image(systemName: "asterisk").font(.system(size: size + 1, weight: .bold))
            case .dot: Circle().frame(width: size * 0.7, height: size * 0.7)
            case .square: RoundedRectangle(cornerRadius: 1.5).frame(width: size * 0.7, height: size * 0.7)
            case .heart: Image(systemName: "heart").font(.system(size: size, weight: .semibold))
            }
        }
        .foregroundStyle(color)
    }
}

private struct PixelCross: View {
    var body: some View {
        Canvas { ctx, size in
            let u = size.width / 5
            for (x, y) in [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4), (4, 0), (3, 1), (1, 3), (0, 4)] {
                ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: u, height: u)), with: .foreground)
            }
        }
    }
}

struct CloseButton: View {
    let style: CloseStyle
    let color: Color
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            CloseGlyph(style: style, color: color).opacity(hover ? 1 : 0.6).frame(width: 22, height: NoteMetrics.titleHeight)
        }
        .buttonStyle(.plain).onHover { hover = $0 }.help(L("note.close"))
    }
}

// MARK: Déplacement à la main

extension Notification.Name { static let noteDragEnded = Notification.Name("mSTICKNoteDragEnded") }

/// Retient la fenêtre qui porte la vue (pour la déplacer même quand la souris sort de son cadre).
final class WindowBox { weak var window: NSWindow? }

private struct WindowReader: NSViewRepresentable {
    let box: WindowBox
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in box.window = v?.window }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { if box.window == nil { box.window = v.window } }
}

/// Déplace la fenêtre quand on tire la vue. Une fenêtre sans barre de titre ne se déplace pas toute seule sous SwiftUI :
/// on suit donc la souris à la main. À la fin du geste, `noteDragEnded` permet à l'Auto Stack d'empiler.
struct WindowDrag: ViewModifier {
    @State private var box = WindowBox()
    @State private var start: (mouse: NSPoint, origin: NSPoint)?

    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .background(WindowReader(box: box))
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in
                    guard let w = box.window else { return }
                    let mouse = NSEvent.mouseLocation
                    if start == nil { start = (mouse, w.frame.origin) }
                    guard let s = start else { return }
                    w.setFrameOrigin(NSPoint(x: s.origin.x + mouse.x - s.mouse.x, y: s.origin.y + mouse.y - s.mouse.y))
                }
                .onEnded { _ in
                    start = nil
                    if let w = box.window { NotificationCenter.default.post(name: .noteDragEnded, object: w) }
                })
    }
}

extension View { func windowDrag() -> some View { modifier(WindowDrag()) } }

/// Fond qui déplace la fenêtre (espaces vides d'une barre).
struct WindowDragArea: View {
    var body: some View { Color.clear.windowDrag() }
}

import AppKit
import SwiftUI
import mSTICKCore

final class FanPanel: NSPanel { override var canBecomeKey: Bool { true } }

@MainActor
final class FanModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var index = 0
    var onOpen: (UUID) -> Void = { _ in }
    var onLibrary: () -> Void = {}
    func move(_ step: Int) {
        guard !notes.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { index = min(max(index + step, 0), notes.count - 1) }
    }
}

/// Le Fan : les notes en éventail comme un jeu de cartes. Flèches ou glissement du pavé pour feuilleter, ⏎ pour ouvrir,
/// ⎋ pour fermer ; taper du texte crée une nouvelle note. Rien ne tourne tant que le Fan est fermé.
@MainActor
final class FanController: NSObject, NSWindowDelegate {
    private let store: NoteStore
    private let model = FanModel()
    private var panel: NSPanel?
    private var monitor: Any?
    private var scrollAccum: CGFloat = 0
    private var shownAt = Date.distantPast
    private var outside: Any?
    var onNewNote: (String) -> Void = { _ in }

    init(store: NoteStore, open: @escaping (UUID) -> Void, library: @escaping () -> Void) {
        self.store = store
        super.init()
        model.onOpen = { [weak self] id in self?.hide(); open(id) }
        model.onLibrary = { [weak self] in self?.hide(); library() }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        model.notes = store.active.sorted { $0.updatedAt > $1.updatedAt }
        model.index = 0
        let size = NSSize(width: 640, height: 360)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2)
        let p = FanPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: FanView(model: model))
        panel = p
        p.alphaValue = 0
        shownAt = Date()
        p.present()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; p.animator().alphaValue = 1 }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in self?.handle(event) ?? event }
        outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in // clic hors du Fan, dans une autre appli
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let outside { NSEvent.removeMonitor(outside) }
        outside = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil // libère la vue : plus rien en mémoire une fois fermé
    }

    /// Le Fan se ferme quand il perd le clavier ; pas dans la fraction de seconde où l'activation de l'appli se met en place.
    func windowDidResignKey(_ notification: Notification) { if Date().timeIntervalSince(shownAt) > 0.6 { hide() } }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isVisible else { return event }
        if event.type == .scrollWheel {
            scrollAccum += abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : -event.scrollingDeltaY
            if abs(scrollAccum) > 24 { model.move(scrollAccum > 0 ? -1 : 1); scrollAccum = 0 }
            return nil
        }
        switch event.keyCode {
        case 123, 126: model.move(-1)
        case 124, 125: model.move(1)
        case 36, 76: if model.notes.indices.contains(model.index) { model.onOpen(model.notes[model.index].id) } else { hide(); onNewNote("") }
        case 53: hide()
        default:
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.contains(.command), !mods.contains(.control), let chars = event.characters, let c = chars.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(c), c.value < 0xF700 else { return event }
            hide(); onNewNote(chars)
        }
        return nil
    }
}

struct FanView: View {
    @ObservedObject var model: FanModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            if model.notes.isEmpty {
                Text(L("fan.empty")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
            }
            ZStack {
                ForEach(Array(model.notes.enumerated()), id: \.element.id) { i, note in
                    let d = i - model.index
                    if abs(d) <= 4 {
                        FanCard(note: note, dark: true)
                            .scaleEffect(1 - CGFloat(abs(d)) * 0.06)
                            .rotationEffect(.degrees(Double(d) * 3.2), anchor: .bottom)
                            .offset(x: CGFloat(d) * 62, y: CGFloat(abs(d)) * 5)
                            .opacity(1 - Double(abs(d)) * 0.14)
                            .zIndex(Double(-abs(d)))
                            .onTapGesture { if d == 0 { model.onOpen(note.id) } else { model.move(d) } }
                    }
                }
            }
            .offset(y: -14)
            VStack {
                Spacer()
                HStack {
                    Text(L("fan.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                    Spacer()
                    if !model.notes.isEmpty { Text("\(model.index + 1) / \(model.notes.count)").socle(Socle.T.monoSm).foregroundStyle(Socle.C.textMuted) }
                    Button(L("fan.library")) { model.onLibrary() }.buttonStyle(.link).font(.system(size: 11))
                }
                .padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
        .padding(8)
    }
}

private struct FanCard: View {
    let note: Note
    let dark: Bool
    var body: some View {
        let t = NoteTheme(color: note.color, dark: dark)
        VStack(spacing: 0) {
            Text(note.displayTitle(fallback: L("note.untitled"))).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.accent).lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: NoteMetrics.titleHeight)
            Text(note.body.isEmpty ? " " : String(note.body.prefix(220))).font(.system(size: 12)).foregroundStyle(t.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.horizontal, 12).padding(.bottom, 10)
        }
        .frame(width: 250, height: 190)
        .background(t.bg)
        .clipShape(RoundedRectangle(cornerRadius: NoteMetrics.corner))
        .overlay(RoundedRectangle(cornerRadius: NoteMetrics.corner).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

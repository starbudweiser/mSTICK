import AppKit
import SwiftUI
import mSTICKCore

final class NotePanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Les notes ouvertes : une fenêtre flottante par note, qui garde sa place d'une ouverture à l'autre.
@MainActor
final class NoteWindows: NSObject, NSWindowDelegate {
    let store: NoteStore
    var deckAnchor: (() -> (frame: NSRect, edge: DeckEdge)?)?
    var openSettings: () -> Void = {}
    private var panels: [UUID: NotePanel] = [:]
    private var models: [UUID: NoteViewModel] = [:]
    private(set) var lastOpened: UUID?
    private var hidden = false
    private let defaults = UserDefaults.standard

    init(store: NoteStore) { self.store = store }

    var isAnyOpen: Bool { !panels.isEmpty }

    func isOpen(_ id: UUID) -> Bool { panels[id] != nil }

    // MARK: Ouverture

    func open(_ id: UUID, tabFrame: NSRect? = nil, quietly: Bool = false, frame: NSRect? = nil) {
        if let existing = panels[id] { reveal(existing, quietly: quietly); return }
        guard store.note(id) != nil else { return }
        let vm = NoteViewModel(id: id, store: store)
        vm.onClose = { [weak self] in self?.close(id) }
        vm.onDelete = { [weak self] in self?.deleteWithUndo(id) }
        let host = NSHostingView(rootView: NoteView(vm: vm, store: store))
        host.wantsLayer = true
        host.layer?.cornerRadius = 10
        host.layer?.masksToBounds = true
        let panel = NotePanel(contentRect: frame ?? place(id, tabFrame: tabFrame), styleMask: [.borderless, .resizable],
                              backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false // un panneau se masque sinon dès que l'appli (sans Dock) n'est plus active
        panel.minSize = NSSize(width: 220, height: 150)
        panel.collectionBehavior = Prefs.shared.showOverFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace]
        panel.delegate = self
        panel.keyHandler = { [weak self, weak panel] event in
            guard let self, let panel else { return false }
            return self.handle(event, id: id, panel: panel)
        }
        applyLevel(panel, pinned: store.note(id)?.pinned ?? false)
        panels[id] = panel; models[id] = vm
        lastOpened = id
        reveal(panel, quietly: quietly)
    }

    private func reveal(_ panel: NotePanel, quietly: Bool) {
        if quietly { panel.orderFront(nil) } else { panel.present() }
    }

    private func applyLevel(_ panel: NSPanel, pinned: Bool) { panel.level = pinned ? .floating : .normal }

    /// Met à jour ce qui dépend de la note (épinglage) ; appelé quand le magasin change.
    func refresh() {
        for (id, panel) in panels {
            guard let note = store.note(id) else { close(id, deleteIfEmpty: false); continue }
            applyLevel(panel, pinned: note.pinned)
        }
    }

    func close(_ id: UUID, deleteIfEmpty: Bool = true) {
        guard let panel = panels[id] else { return }
        panels[id] = nil; models[id] = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
        if deleteIfEmpty, let n = store.note(id), n.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           n.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.delete([id]) } // note vide : rien à garder
    }

    func closeAll() { for id in Array(panels.keys) { close(id) } }

    func toggleHidden() {
        hidden.toggle()
        for panel in panels.values { hidden ? panel.orderOut(nil) : panel.orderFront(nil) }
    }

    func openNeighbor(of id: UUID, step: Int) {
        let list = store.active
        guard let i = list.firstIndex(where: { $0.id == id }), !list.isEmpty else { return }
        let next = list[(i + step + list.count) % list.count].id
        if let from = panels[id] { UserDefaults.standard.set(NSStringFromRect(from.frame), forKey: "frame." + next.uuidString) }
        open(next)
        close(id, deleteIfEmpty: false)
    }

    private func deleteWithUndo(_ id: UUID) {
        let frame = panels[id]?.frame
        close(id, deleteIfEmpty: false)
        let gone = store.delete([id])
        guard !gone.isEmpty else { return }
        Toast.show(L("toast.deleted"), action: L("toast.undo")) { [weak self] in
            self?.store.restore(gone)
            if let frame { self?.defaults.set(NSStringFromRect(frame), forKey: "frame." + id.uuidString) }
            self?.open(id)
        }
    }

    // MARK: Raccourcis dans une note

    private func handle(_ event: NSEvent, id: UUID, panel: NotePanel) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { return false }
        let key = event.charactersIgnoringModifiers ?? ""
        let editor = models[id]?.editor
        let shift = mods.contains(.shift)
        switch (key, event.keyCode, shift) {
        case (_, 51, true): deleteWithUndo(id)
        case ("w", _, false): close(id)
        case ("]", _, _), (_, 30, false): openNeighbor(of: id, step: 1)
        case ("[", _, _), (_, 33, false): openNeighbor(of: id, step: -1)
        case (".", _, false), (_, 47, false):
            let colors = Prefs.shared.allColors
            if let note = store.note(id), let i = colors.firstIndex(of: note.color) { store.update(id) { $0.color = colors[(i + 1) % colors.count] } }
            else { store.update(id) { $0.color = colors[0] } }
        case (",", _, false): openSettings()
        case ("b", _, false): editor?.toggleWrap("**")
        case ("i", _, false): editor?.toggleWrap("*")
        case ("u", _, false): editor?.toggleWrap("<u>", "</u>")
        case ("f", _, false):
            let item = NSMenuItem(); item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
            editor?.performFindPanelAction(item)
        default: return false
        }
        return true
    }

    // MARK: Emplacement

    private func place(_ id: UUID, tabFrame: NSRect?) -> NSRect {
        let size = NSSize(width: 300, height: 300)
        if let saved = defaults.string(forKey: "frame." + id.uuidString) {
            let r = NSRectFromString(saved)
            if r.width > 100, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) { return r }
        }
        if let last = defaults.string(forKey: "lastFrame") { // une nouvelle note s'ouvre là où la dernière a été posée
            let r = NSRectFromString(last)
            if r.width > 100, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) {
                return NSRect(x: r.origin.x + 24 * CGFloat(panels.count % 4), y: r.origin.y - 24 * CGFloat(panels.count % 4), width: r.width, height: r.height)
            }
        }
        guard let anchor = deckAnchor?(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor.frame) }) ?? NSScreen.main else {
            let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 800, height: 600)
            return NSRect(x: vf.midX - 150, y: vf.midY - 150, width: size.width, height: size.height)
        }
        let vf = screen.visibleFrame
        var origin: NSPoint
        switch anchor.edge {
        case .right: origin = NSPoint(x: anchor.frame.minX - size.width - 14, y: (tabFrame?.midY ?? anchor.frame.midY) - size.height / 2)
        case .left: origin = NSPoint(x: anchor.frame.maxX + 14, y: (tabFrame?.midY ?? anchor.frame.midY) - size.height / 2)
        case .bottom: origin = NSPoint(x: (tabFrame?.midX ?? anchor.frame.midX) - size.width / 2, y: anchor.frame.maxY + 14)
        case .top: origin = NSPoint(x: (tabFrame?.midX ?? anchor.frame.midX) - size.width / 2, y: anchor.frame.minY - size.height - 14)
        }
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        return NSRect(origin: origin, size: size)
    }

    private func remember(_ window: NSWindow?) {
        guard let panel = window as? NotePanel, let id = panels.first(where: { $0.value === panel })?.key else { return }
        defaults.set(NSStringFromRect(panel.frame), forKey: "frame." + id.uuidString)
        defaults.set(NSStringFromRect(panel.frame), forKey: "lastFrame")
    }

    func windowDidMove(_ notification: Notification) { remember(notification.object as? NSWindow) }
    func windowDidEndLiveResize(_ notification: Notification) { remember(notification.object as? NSWindow) }
    func windowDidBecomeKey(_ notification: Notification) {
        if let panel = notification.object as? NotePanel, let id = panels.first(where: { $0.value === panel })?.key { lastOpened = id }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel, let id = panels.first(where: { $0.value === panel })?.key else { return }
        close(id)
    }
}

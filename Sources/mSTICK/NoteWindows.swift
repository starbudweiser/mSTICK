import AppKit
import SwiftUI
import mSTICKCore

/// Le premier clic sur une note qui n'a pas le focus agit tout de suite (barre d'une pile, glissement, case à cocher).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotePanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Une pile : des notes alignées sous une même barre ; une seule est ouverte, les autres ne montrent que leur titre.
struct NoteStack: Codable, Equatable {
    var ids: [UUID]
    var active: UUID
    var left: CGFloat
    var top: CGFloat          // bord haut (coordonnées écran, y vers le haut)
    var width: CGFloat
    var bodyHeight: CGFloat   // hauteur de la note ouverte
}

/// Les notes ouvertes : une fenêtre par note, posée librement sur le bureau, qui garde sa place d'une session à l'autre.
@MainActor
final class NoteWindows: NSObject, NSWindowDelegate {
    let store: NoteStore
    var openSettings: () -> Void = {}
    var openLibrary: () -> Void = {}
    var onNew: () -> Void = {}
    private(set) var panels: [UUID: NotePanel] = [:]
    private var models: [UUID: NoteViewModel] = [:]
    private(set) var stacks: [NoteStack] = []
    private(set) var lastOpened: UUID?
    private var hidden = false
    private var applying = false
    private var peekID: UUID?
    private var peekOpenedIt = false
    private var saveWork: DispatchWorkItem?
    private let defaults = UserDefaults.standard

    init(store: NoteStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(forName: .noteDragEnded, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { if let w = n.object as? NotePanel { self?.dragEnded(w) } }
        }
    }

    var isAnyOpen: Bool { !panels.isEmpty }
    func isOpen(_ id: UUID) -> Bool { panels[id] != nil }
    private func id(of panel: NSWindow?) -> UUID? { panels.first { $0.value === panel }?.key }

    // MARK: Ouverture

    func open(_ id: UUID, quietly: Bool = false, frame: NSRect? = nil) {
        if let existing = panels[id] { quietly ? existing.orderFront(nil) : existing.present(); activateIfStacked(id); return }
        guard store.note(id) != nil else { return }
        let vm = NoteViewModel(id: id, store: store)
        vm.editing = store.note(id)?.body.isEmpty ?? true // note neuve : on écrit tout de suite ; sinon rendu
        vm.onClose = { [weak self] in self?.close(id) }
        vm.onDelete = { [weak self] in self?.deleteWithUndo(id) }
        vm.onActivate = { [weak self] in self?.activate(id) }
        vm.onUnstack = { [weak self] in self?.unstack(id) }
        vm.onRemoveFromStack = { [weak self] in self?.removeFromStack(id) }
        vm.onCloseStack = { [weak self] in self?.closeStack(id) }
        vm.onColorStack = { [weak self] mode in self?.colorStack(id, mode) }
        vm.onCommand = { [weak self] cmd in self?.command(id, cmd) }
        let host = FirstMouseHostingView(rootView: NoteView(vm: vm, store: store))
        host.wantsLayer = true
        host.layer?.cornerRadius = NoteMetrics.corner
        host.layer?.masksToBounds = true
        let panel = NotePanel(contentRect: frame ?? place(id), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false // sinon le panneau se masque dès que l'appli (sans Dock) n'est plus active
        panel.minSize = NSSize(width: 220, height: 120)
        panel.delegate = self
        panel.keyHandler = { [weak self, weak panel] event in
            guard let self, let panel else { return false }
            return self.handle(event, id: id, panel: panel)
        }
        panels[id] = panel; models[id] = vm
        remember(id, panel.frame)
        applyBehavior(panel, store.note(id))
        lastOpened = id
        saveState()
        if quietly { panel.orderFront(nil); return }
        panel.alphaValue = 0
        panel.present()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.2; panel.animator().alphaValue = 1 }
    }

    /// Met le curseur en fin de texte et le focus dans l'éditeur (note créée en tapant dans le Fan, par exemple).
    func focusEnd(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panels[id], let tv = self.models[id]?.editor else { return }
            panel.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
    }

    /// Niveau et bureaux d'une note : flottante, collée au bureau, visible sur tous les bureaux.
    private func applyBehavior(_ panel: NotePanel, _ note: Note?) {
        let prefs = Prefs.shared
        if note?.pinned == true { panel.level = .floating }
        else if note?.glued == true { panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) }
        else { panel.level = .normal }
        var behavior: NSWindow.CollectionBehavior = prefs.showOverFullScreen ? [.fullScreenAuxiliary] : []
        behavior.insert(note?.allDesktops == true ? .canJoinAllSpaces : .moveToActiveSpace)
        panel.collectionBehavior = behavior
        panel.appearance = switch prefs.appearance { case .dark: NSAppearance(named: .darkAqua); case .light: NSAppearance(named: .aqua); case .auto: nil }
    }

    /// Met à jour ce qui dépend de la note (niveau, bureaux, apparence) ; appelé quand le magasin ou les réglages changent.
    func refresh() {
        for (id, panel) in panels {
            guard let note = store.note(id), !note.archived else { close(id, deleteIfEmpty: false); continue }
            if id != peekID { applyBehavior(panel, note) }
        }
    }

    func close(_ id: UUID, deleteIfEmpty: Bool = true) {
        guard let panel = panels[id] else { return }
        if let i = stackIndex(of: id) { removeMember(id, from: i) }
        panels[id] = nil; models[id] = nil
        if peekID == id { peekID = nil }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
        saveState()
        if deleteIfEmpty, let n = store.note(id), n.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           n.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.delete([id]) } // note vide : rien à garder
    }

    func closeAll() { for id in Array(panels.keys) { close(id) } }

    func toggleHidden() {
        hidden.toggle()
        for panel in panels.values { hidden ? panel.orderOut(nil) : panel.orderFront(nil) }
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

    // MARK: Commandes « / » et raccourcis

    private func command(_ id: UUID, _ cmd: String) {
        switch cmd {
        case "float": store.update(id) { $0.pinned.toggle(); if $0.pinned { $0.glued = nil } }
        case "glue": store.update(id) { $0.glued = ($0.glued == true) ? nil : true; if $0.glued == true { $0.pinned = false } }
        case "desktops": store.update(id) { $0.allDesktops = ($0.allDesktops == true) ? nil : true }
        case "color": cycleColor(id)
        case "archive": store.setArchived([id], true)
        case "delete": deleteWithUndo(id)
        case "close": close(id)
        case "new": onNew()
        case "library": openLibrary()
        case "settings": openSettings()
        default: break
        }
    }

    private func cycleColor(_ id: UUID) {
        let colors = Prefs.shared.allColors
        guard let note = store.note(id) else { return }
        let i = colors.firstIndex(of: note.color) ?? -1
        store.update(id) { $0.color = colors[(i + 1) % colors.count] }
    }

    private func handle(_ event: NSEvent, id: UUID, panel: NotePanel) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { return false }
        let key = event.charactersIgnoringModifiers ?? ""
        let editor = models[id]?.editor
        let shift = mods.contains(.shift)
        switch (key, event.keyCode, shift) {
        case (_, 51, true): deleteWithUndo(id)
        case ("w", _, false): close(id)
        case ("n", _, false): onNew()
        case (".", _, false), (_, 47, false): cycleColor(id)
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

    // MARK: Peek : la dernière note passe au-dessus de tout, une seconde pression la range

    func peek() {
        if let id = peekID, panels[id] != nil {
            if peekOpenedIt { close(id, deleteIfEmpty: false) } else if let p = panels[id] { applyBehavior(p, store.note(id)); p.orderBack(nil) }
            peekID = nil
            return
        }
        guard let id = lastOpened.flatMap({ store.note($0) != nil ? $0 : nil }) ?? store.active.first?.id else { onNew(); return }
        peekOpenedIt = panels[id] == nil
        open(id)
        guard let panel = panels[id] else { return }
        peekID = id
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // aussi au-dessus d'une appli en plein écran
        panel.present()
    }

    // MARK: Emplacement

    /// Où ouvrir une note : sa dernière place si elle est encore sur un écran, sinon en cascade au centre de l'écran sous la souris.
    private func place(_ id: UUID) -> NSRect {
        var size = NSSize(width: 320, height: 280)
        if let saved = defaults.string(forKey: "frame." + id.uuidString) {
            let r = NSRectFromString(saved)
            if r.width > 100, r.height > 60 {
                size = r.size
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) { return r }
            }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let step = CGFloat(panels.count % 8) * 26
        return NSRect(x: vf.midX - size.width / 2 + step, y: vf.midY - size.height / 2 - step, width: size.width, height: size.height)
    }

    private func remember(_ id: UUID, _ frame: NSRect) { defaults.set(NSStringFromRect(frame), forKey: "frame." + id.uuidString) }

    // MARK: Piles

    private func stackIndex(of id: UUID) -> Int? { stacks.firstIndex { $0.ids.contains(id) } }

    private func above(_ id: UUID, in s: NoteStack) -> CGFloat {
        var h: CGFloat = 0
        for other in s.ids { if other == id { break }; h += other == s.active ? s.bodyHeight : NoteMetrics.titleHeight }
        return h
    }

    /// Range les fenêtres d'une pile : chaque note sous la précédente, la note ouverte à sa pleine hauteur.
    private func layout(_ i: Int, skipping: NSWindow? = nil, animate: Bool = false) {
        guard stacks.indices.contains(i) else { return }
        let s = stacks[i]
        var y = s.top
        applying = true
        for id in s.ids {
            guard let p = panels[id] else { continue }
            let open = id == s.active
            let h = open ? s.bodyHeight : NoteMetrics.titleHeight
            models[id]?.collapsed = !open
            p.minSize = NSSize(width: 220, height: open ? 120 : NoteMetrics.titleHeight)
            p.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: open ? CGFloat.greatestFiniteMagnitude : NoteMetrics.titleHeight)
            let frame = NSRect(x: s.left, y: y - h, width: s.width, height: h)
            if p !== skipping, p.frame != frame { p.setFrame(frame, display: true, animate: animate) }
            y -= h
        }
        applying = false
        scheduleSave()
    }

    private func syncStackFlags() {
        for (id, vm) in models { vm.inStack = stackIndex(of: id) != nil; if !vm.inStack { vm.collapsed = false } }
        for (id, p) in panels where stackIndex(of: id) == nil { p.minSize = NSSize(width: 220, height: 120); p.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude); _ = id }
    }

    /// `joining` rejoint la pile de `target` (ou forme une pile avec lui).
    func stack(_ joining: UUID, onto target: UUID) {
        guard joining != target, let pj = panels[joining], let pt = panels[target], stackIndex(of: joining) == nil else { return }
        if let i = stackIndex(of: target) {
            stacks[i].ids.append(joining); stacks[i].active = joining
            stacks[i].bodyHeight = max(stacks[i].bodyHeight, pj.frame.height)
            syncStackFlags(); layout(i, animate: true)
        } else {
            let s = NoteStack(ids: [target, joining], active: joining, left: pt.frame.minX, top: pt.frame.maxY, width: pt.frame.width, bodyHeight: max(pt.frame.height, pj.frame.height))
            stacks.append(s)
            syncStackFlags(); layout(stacks.count - 1, animate: true)
        }
    }

    func activate(_ id: UUID) {
        guard let i = stackIndex(of: id), stacks[i].active != id else { return }
        stacks[i].active = id
        layout(i, animate: true)
        panels[id]?.makeKey()
    }

    private func activateIfStacked(_ id: UUID) { activate(id) }

    private func removeMember(_ id: UUID, from i: Int) {
        stacks[i].ids.removeAll { $0 == id }
        if stacks[i].active == id, let first = stacks[i].ids.last { stacks[i].active = first }
        if stacks[i].ids.count < 2 {
            let s = stacks.remove(at: i)
            if let last = s.ids.first, let p = panels[last] {
                applying = true
                p.minSize = NSSize(width: 220, height: 120); p.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                p.setFrame(NSRect(x: s.left, y: s.top - s.bodyHeight, width: s.width, height: s.bodyHeight), display: true)
                applying = false
                remember(last, p.frame)
            }
        } else { layout(i, animate: true) }
        syncStackFlags()
    }

    func removeFromStack(_ id: UUID) {
        guard let i = stackIndex(of: id), let p = panels[id] else { return }
        let s = stacks[i]
        removeMember(id, from: i)
        applying = true
        p.setFrame(NSRect(x: s.left + s.width + 24, y: s.top - s.bodyHeight, width: s.width, height: s.bodyHeight), display: true, animate: true)
        applying = false
        remember(id, p.frame)
    }

    func unstack(_ id: UUID) {
        guard let i = stackIndex(of: id) else { return }
        let s = stacks.remove(at: i)
        syncStackFlags()
        applying = true
        for (k, nid) in s.ids.enumerated() {
            guard let p = panels[nid] else { continue }
            let f = NSRect(x: s.left + CGFloat(k) * 32, y: s.top - s.bodyHeight - CGFloat(k) * 32, width: s.width, height: s.bodyHeight)
            p.setFrame(f, display: true, animate: true)
            remember(nid, f)
        }
        applying = false
        scheduleSave()
    }

    func closeStack(_ id: UUID) {
        guard let i = stackIndex(of: id) else { return }
        for nid in stacks[i].ids { close(nid) }
    }

    func colorStack(_ id: UUID, _ mode: StackColoring) {
        guard let i = stackIndex(of: id) else { return }
        let ids = stacks[i].ids
        let all = Prefs.shared.allColors
        let spectrum = ["orange", "yellow", "green", "teal", "blue", "purple", "pink"]
        for (k, nid) in ids.enumerated() {
            let color: String
            switch mode {
            case .spectrum: color = spectrum[Int((Double(k) / Double(max(ids.count - 1, 1)) * Double(spectrum.count - 1)).rounded())]
            case .unique: color = all[k % all.count]
            case .same: color = store.note(ids[0])?.color ?? "yellow"
            }
            store.update(nid) { $0.color = color }
        }
    }

    /// Auto Stack : une note déposée sur la barre ou le corps d'une autre s'empile avec elle.
    private func dragEnded(_ panel: NotePanel) {
        guard Prefs.shared.autoStack, let id = id(of: panel), stackIndex(of: id) == nil else { return }
        let point = NSPoint(x: panel.frame.midX, y: panel.frame.maxY - NoteMetrics.titleHeight / 2)
        guard let (tid, _) = panels.first(where: { $0.key != id && $0.value.isVisible && $0.value.frame.contains(point) }) else { return }
        stack(id, onto: tid)
    }

    // MARK: Sauvegarde de l'état (notes ouvertes et piles)

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveState() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveState() {
        defaults.set(panels.keys.map(\.uuidString), forKey: "open")
        defaults.set(try? JSONEncoder().encode(stacks), forKey: "stacks")
    }

    /// Au lancement : rouvre les notes qui étaient ouvertes, à leur place, et refait les piles.
    func restore() {
        let ids = (defaults.stringArray(forKey: "open") ?? []).compactMap(UUID.init(uuidString:))
        let saved = defaults.data(forKey: "stacks").flatMap { try? JSONDecoder().decode([NoteStack].self, from: $0) } ?? [] // à lire avant d'ouvrir : ouvrir une note réécrit l'état
        for id in ids { if let n = store.note(id), !n.archived { open(id, quietly: true) } }
        for var s in saved {
            s.ids = s.ids.filter { panels[$0] != nil }
            guard s.ids.count >= 2, !s.ids.contains(where: { stackIndex(of: $0) != nil }) else { continue }
            if !s.ids.contains(s.active) { s.active = s.ids[0] }
            stacks.append(s)
        }
        syncStackFlags()
        for i in stacks.indices { layout(i) }
    }

    // MARK: Fenêtres

    func windowDidMove(_ notification: Notification) {
        guard !applying, let panel = notification.object as? NotePanel, let id = id(of: panel) else { return }
        if let i = stackIndex(of: id) {
            stacks[i].left = panel.frame.minX
            stacks[i].top = panel.frame.maxY + above(id, in: stacks[i])
            layout(i, skipping: panel)
        } else { remember(id, panel.frame); scheduleSave() }
    }

    func windowDidResize(_ notification: Notification) {
        guard !applying, let panel = notification.object as? NotePanel, let id = id(of: panel) else { return }
        if let i = stackIndex(of: id), stacks[i].active == id {
            stacks[i].width = panel.frame.width; stacks[i].bodyHeight = panel.frame.height; stacks[i].left = panel.frame.minX
            stacks[i].top = panel.frame.maxY + above(id, in: stacks[i])
            layout(i, skipping: panel)
        } else if stackIndex(of: id) == nil { remember(id, panel.frame) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let panel = notification.object as? NotePanel, let id = id(of: panel) { lastOpened = id }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel, let id = id(of: panel) else { return }
        close(id)
    }
}

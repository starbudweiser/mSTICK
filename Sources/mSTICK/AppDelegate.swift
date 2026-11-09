import AppKit
import Combine
import SwiftUI
import mSTICKCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: NoteStore
    let notes: NoteWindows
    let deck: DeckController
    let allNotes = AllNotesWindow()
    let settings = SettingsWindow()
    let updates = UpdateEngine.shared
    private let prefs = Prefs.shared
    private var statusItem: NSStatusItem?

    override init() {
        let env = ProcessInfo.processInfo.environment
        let service = Bundle.main.bundleIdentifier ?? "fr.stephan.mstick"
        let keyFile = env["MSTICK_KEY_FILE"].map { URL(fileURLWithPath: $0) }
        let key = (try? VaultKey.load(service: service, fileOverride: keyFile)) ?? SymmetricKey(size: .bits256)
        let vault = try! Vault(directory: Vault.defaultDirectory, key: key)
        store = NoteStore(vault: vault)
        notes = NoteWindows(store: store)
        deck = DeckController(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        Socle.brand("mSTICK", color: BrandColor.color)
        store.untitled = L("note.untitled")
        installMainMenu()
        notes.openSettings = { [weak self] in self?.showSettings() }
        notes.deckAnchor = { [weak self] in self?.deck.anchor }
        deck.onOpen = { [weak self] id, frame in self?.notes.open(id, tabFrame: frame) }
        deck.onNew = { [weak self] in self?.newNote() }
        deck.onShowAll = { [weak self] in self?.showAll(.active) }
        store.onExternalChange = { [weak self] _ in self?.notes.refresh() }
        NotificationCenter.default.addObserver(forName: .prefsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPrefs() }
        }
        store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.deck.refresh(); self?.notes.refresh() } }
        }.store(in: &cancellables)

        HotkeyCenter.shared.onPress = { [weak self] action in self?.perform(action) }
        deck.rebuild()
        applyPrefs()

        updates.configure(repo: "mSTICK", lang: { Bundle.main.preferredLocalizations.first ?? "en" })
        updates.autoCheck = { Prefs.shared.autoUpdate }
        updates.start()

        let args = CommandLine.arguments
        if args.contains("--discret-ouvrir") { if let first = store.active.first { notes.open(first.id, quietly: true) } }
        if args.contains("--discret-toutes") { showAll(.all, quietly: true) }
        if args.contains("--discret-reglages") { settings.show(store: store, quietly: true) }
        if args.contains("--deck-ouvert") { deck.fanForTesting() }
        if args.contains("--demo-notes") { demoNotes() }
        if let i = args.firstIndex(of: "--zones-test"), args.indices.contains(i + 2), let x = Double(args[i + 1]), let y = Double(args[i + 2]) { deck.showZonesForTesting(NSPoint(x: x, y: y)) }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Démo : ouvre toutes les notes en cascade près du deck, sans prendre le focus.
    private func demoNotes() {
        guard let screen = NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        for (i, n) in store.active.enumerated() {
            let x = vf.maxX - 70 - 320 - CGFloat(i) * 120
            let y = vf.midY - 160 + CGFloat(i % 2 == 0 ? 60 : -60) - CGFloat(i) * 6
            notes.open(n.id, quietly: true, frame: NSRect(x: max(vf.minX + 20, x), y: y, width: 320, height: 330))
        }
        deck.fanForTesting()
    }

    func applicationWillTerminate(_ notification: Notification) { store.flush() }

    /// Relancer l'appli depuis le Finder ouvre « Toutes les notes ».
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showAll(.active)
        return false
    }

    // MARK: Réglages appliqués

    private func applyPrefs() {
        store.syncFolder = prefs.syncEnabled && !prefs.syncPath.isEmpty ? URL(fileURLWithPath: prefs.syncPath) : nil
        store.markdownFolder = prefs.markdownEnabled && !prefs.markdownPath.isEmpty ? URL(fileURLWithPath: prefs.markdownPath) : nil
        if deckScreensChanged() { deck.rebuild() }
        bindHotkeys()
        installStatusItem()
    }

    private var lastScreenChoice: String?
    private func deckScreensChanged() -> Bool {
        defer { lastScreenChoice = prefs.screenChoice }
        return lastScreenChoice != prefs.screenChoice
    }

    private func bindHotkeys() {
        let list = HotkeyAction.allCases.compactMap { a in prefs.hotkey(a).map { (a, $0) } }
        HotkeyCenter.shared.register(list)
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .newNote: newNote()
        case .reopenLast:
            if let id = notes.lastOpened, store.note(id) != nil { notes.open(id) } else if let first = store.active.first { notes.open(first.id) }
        case .allNotes: showAll(.all)
        case .archive: showAll(.archived)
        case .moveDeck: prefs.edge = prefs.edge.next
        case .hideAll: deck.toggleHidden(); notes.toggleHidden()
        }
    }

    // MARK: Actions

    func newNote() {
        let colors = NoteColor.palette.map(\.id)
        let note = store.create(color: colors[store.notes.count % colors.count])
        notes.open(note.id)
    }

    func showAll(_ filter: NoteFilter, quietly: Bool = false) {
        allNotes.show(store: store, filter: filter, open: { [weak self] id in
            self?.notes.open(id)
        }, quietly: quietly)
    }

    func showSettings() { settings.show(store: store) }

    // MARK: Barre des menus (le menu s'ouvre sous l'icône : jamais `statusItem.menu`, sinon macOS le décale sur plusieurs écrans)

    private func installStatusItem() {
        if !prefs.menuBarIcon {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item); statusItem = nil }
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarImage()
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// Silhouette monochrome d'une note adhésive au coin replié (image « modèle » : suit le thème de la barre).
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3.5, y: 2)); path.line(to: NSPoint(x: 14.5, y: 2)); path.line(to: NSPoint(x: 14.5, y: 10.5))
            path.line(to: NSPoint(x: 10.5, y: 15)); path.line(to: NSPoint(x: 3.5, y: 15)); path.close()
            NSColor.black.setFill(); path.fill()
            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: 10.5, y: 15)); fold.line(to: NSPoint(x: 10.5, y: 10.5)); fold.line(to: NSPoint(x: 14.5, y: 10.5)); fold.close()
            NSColor.black.withAlphaComponent(0.45).setFill(); fold.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusClicked() {
        guard let button = statusItem?.button else { return }
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY + 4 : -4), in: button)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, key: HotkeyAction? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let key, let hk = prefs.hotkey(key) { item.badge = NSMenuItemBadge(string: KeyName.label(hk)) }
            menu.addItem(item)
        }
        add(L("menu.new"), #selector(menuNew), key: .newNote)
        add(L("menu.all"), #selector(menuAll), key: .allNotes)
        add(L("menu.archive"), #selector(menuArchive), key: .archive)
        menu.addItem(.separator())
        let place = NSMenuItem(title: L("menu.place"), action: nil, keyEquivalent: "")
        place.submenu = placeMenu()
        menu.addItem(place)
        add(L("menu.movedeck"), #selector(menuMove), key: .moveDeck)
        add(L("menu.hide"), #selector(menuHide), key: .hideAll)
        menu.addItem(.separator())
        add(L("menu.settings"), #selector(menuSettings))
        switch updates.state {
        case .available(let plan): add(L("update.install", plan.target.version), #selector(menuInstallUpdate))
        case .downloading, .verifying, .installing:
            let busy = NSMenuItem(title: L("update.installing"), action: nil, keyEquivalent: ""); busy.isEnabled = false; menu.addItem(busy)
        default: add(L("update.check"), #selector(menuCheckUpdate))
        }
        add(L("about.menu"), #selector(menuAbout))
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    /// « Placer le deck » : le bord (haut, bas, gauche, droite) puis l'écran (principal, secondaire, tous).
    private func placeMenu() -> NSMenu {
        let sub = NSMenu()
        for edge in [DeckEdge.top, .bottom, .left, .right] {
            let item = NSMenuItem(title: L("edge." + edge.rawValue), action: #selector(menuEdge(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = edge.rawValue
            item.state = prefs.edge == edge ? .on : .off
            sub.addItem(item)
        }
        sub.addItem(.separator())
        var choices: [(String, String)] = [("main", L("screens.main"))]
        for s in NSScreen.screens.dropFirst() { choices.append((String(s.displayID), L("screens.secondary", s.localizedName))) }
        if NSScreen.screens.count > 1 { choices.append(("all", L("screens.all"))) }
        for (id, title) in choices {
            let item = NSMenuItem(title: title, action: #selector(menuScreen(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = id
            item.state = prefs.screenChoice == id ? .on : .off
            sub.addItem(item)
        }
        return sub
    }

    @objc private func menuEdge(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let e = DeckEdge(rawValue: raw) { prefs.edge = e } }
    @objc private func menuScreen(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { prefs.screenChoice = id } }
    @objc private func menuNew() { newNote() }
    @objc private func menuAll() { showAll(.all) }
    @objc private func menuArchive() { showAll(.archived) }
    @objc private func menuMove() { prefs.edge = prefs.edge.next }
    @objc private func menuHide() { deck.toggleHidden(); notes.toggleHidden() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuCheckUpdate() { updates.checkNow() }
    @objc private func menuInstallUpdate() { if case .available(let plan) = updates.state { updates.present(plan) } }
    @objc private func menuAbout() { About.show() }

    // MARK: Menu principal (porte ⌘C, ⌘V, ⌘W… même sans Dock)

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(); let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window; main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}

import CryptoKit

import AppKit
import Combine
import SwiftUI
import mSTICKCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: NoteStore
    let notes: NoteWindows
    private(set) var fan: FanController!
    private(set) var reminders: ReminderCenter!
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
        super.init()
        fan = FanController(store: store, open: { [weak self] id in self?.notes.open(id) }, library: { [weak self] in self?.showAll(.all) })
        fan.onNewNote = { [weak self] text in self?.newNote(text: text) }
        reminders = ReminderCenter(store: store) { [weak self] id in self?.notes.open(id) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        Socle.brand("mSTICK", color: BrandColor.color)
        store.untitled = L("note.untitled")
        installMainMenu()
        notes.openSettings = { [weak self] in self?.showSettings() }
        notes.openLibrary = { [weak self] in self?.showAll(.all) }
        notes.onNew = { [weak self] in self?.newNote() }
        store.onExternalChange = { [weak self] _ in self?.notes.refresh(); self?.reminders.reschedule() }
        NotificationCenter.default.addObserver(forName: .prefsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPrefs() }
        }
        store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.notes.refresh(); self?.reminders.reschedule() } }
        }.store(in: &cancellables)

        HotkeyCenter.shared.onPress = { [weak self] action in self?.perform(action) }
        applyPrefs()
        notes.restore()
        reminders.reschedule()

        updates.configure(repo: "mSTICK", lang: { Bundle.main.preferredLocalizations.first ?? "en" })
        updates.autoCheck = { Prefs.shared.autoUpdate }
        updates.start()

        let args = CommandLine.arguments
        if args.contains("--discret-ouvrir") { if let first = store.active.first { notes.open(first.id, quietly: true) } }
        if args.contains("--discret-toutes") { showAll(.all, quietly: true) }
        if args.contains("--discret-reglages") { settings.show(store: store, quietly: true) }
        if args.contains("--fan-ouvert") { fan.show() }
        if args.contains("--demo-notes") { demoNotes() }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Démo : ouvre les notes en cascade, puis empile les deux dernières, sans prendre le focus.
    private func demoNotes() {
        guard let screen = NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let list = store.active
        for (i, n) in list.enumerated() {
            notes.open(n.id, quietly: true, frame: NSRect(x: vf.minX + 80 + CGFloat(i) * 150, y: vf.midY - 140 - CGFloat(i % 2) * 70, width: 300, height: 260))
        }
        if list.count >= 4 { notes.stack(list[3].id, onto: list[2].id); if list.count >= 5 { notes.stack(list[4].id, onto: list[2].id) } }
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
        notes.refresh()
        reminders.reschedule()
        bindHotkeys()
        installStatusItem()
    }

    private func bindHotkeys() {
        let list = HotkeyAction.allCases.compactMap { a in prefs.hotkey(a).map { (a, $0) } }
        HotkeyCenter.shared.register(list)
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .newNote: newNote()
        case .fan: fan.toggle()
        case .peek: notes.peek()
        case .library: showAll(.all)
        case .hideAll: notes.toggleHidden()
        }
    }

    // MARK: Actions

    func newNote(text: String = "") {
        let colors = NoteColor.palette.map(\.id)
        let note = store.create(color: colors[store.notes.count % colors.count])
        if !text.isEmpty { store.update(note.id) { $0.body = text } }
        notes.open(note.id)
        notes.focusEnd(note.id)
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
        statusItem?.socleShow(menu)   // Socle : menu placé selon l'écran de l'icône (plusieurs écrans)
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
        add(L("menu.fan"), #selector(menuFan), key: .fan)
        add(L("menu.peek"), #selector(menuPeek), key: .peek)
        add(L("menu.library"), #selector(menuAll), key: .library)
        menu.addItem(.separator())
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

    @objc private func menuNew() { newNote() }
    @objc private func menuAll() { showAll(.all) }
    @objc private func menuFan() { fan.show() }
    @objc private func menuPeek() { notes.peek() }
    @objc private func menuHide() { notes.toggleHidden() }
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

import AppKit
import SwiftUI
import mSTICKCore

extension Notification.Name {
    static let prefsChanged = Notification.Name("mSTICKPrefsChanged")
}

enum DockStyle: String, CaseIterable { case stripes, dots, pile }

/// Écran du deck : « main » (celui de la barre des menus), « all », ou l'identifiant d'un écran précis.
extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    static var primary: NSScreen? { NSScreen.screens.first }
}

/// Marque : couleur du logo, utilisée pour la lettre « m » du nom de l'appli.
enum BrandColor {
    static let ns = NSColor(red: 1.0, green: 0.80, blue: 0.22, alpha: 1)
    static let color = Color(red: 1.0, green: 0.80, blue: 0.22)
}

/// Réglages de l'appli (UserDefaults). Chaque changement prévient l'appli par `.prefsChanged`.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard
    private func changed() { NotificationCenter.default.post(name: .prefsChanged, object: nil) }

    @Published var edge: DeckEdge { didSet { d.set(edge.rawValue, forKey: "edge"); changed() } }
    @Published var dockStyle: DockStyle { didSet { d.set(dockStyle.rawValue, forKey: "dockStyle"); changed() } }
    @Published var keepOpen: Bool { didSet { d.set(keepOpen, forKey: "keepOpen"); changed() } }
    @Published var fanOnClick: Bool { didSet { d.set(fanOnClick, forKey: "fanOnClick"); changed() } }
    @Published var screenChoice: String { didSet { d.set(screenChoice, forKey: "screens"); changed() } }
    @Published var defaultFont: String { didSet { d.set(defaultFont, forKey: "defaultFont"); changed() } }
    @Published var fontSize: Int { didSet { d.set(fontSize, forKey: "fontSize"); changed() } }
    @Published var activationDelay: Double { didSet { d.set(activationDelay, forKey: "activationDelay"); changed() } }
    @Published var showOverFullScreen: Bool { didSet { d.set(showOverFullScreen, forKey: "showOverFullScreen"); changed() } }
    @Published var autoHideToolbar: Bool { didSet { d.set(autoHideToolbar, forKey: "autoHideToolbar"); changed() } }
    @Published var emojiButton: Bool { didSet { d.set(emojiButton, forKey: "emojiButton"); changed() } }
    @Published var menuBarIcon: Bool { didSet { d.set(menuBarIcon, forKey: "menuBarIcon"); changed() } }
    @Published var customColors: [String] { didSet { d.set(customColors, forKey: "customColors"); changed() } }
    @Published var syncEnabled: Bool { didSet { d.set(syncEnabled, forKey: "syncEnabled"); changed() } }
    @Published var syncPath: String { didSet { d.set(syncPath, forKey: "syncPath"); changed() } }
    @Published var markdownEnabled: Bool { didSet { d.set(markdownEnabled, forKey: "markdownEnabled"); changed() } }
    @Published var markdownPath: String { didSet { d.set(markdownPath, forKey: "markdownPath"); changed() } }
    @Published var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "autoUpdate"); changed() } }
    @Published var hotkeys: [String: Hotkey] { didSet { d.set(try? JSONEncoder().encode(hotkeys), forKey: "hotkeys"); changed() } }

    static let fontSizes = [10, 12, 14, 16, 18, 20, 24]

    private init() {
        func bool(_ k: String, _ v: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? v }
        let d = UserDefaults.standard
        edge = DeckEdge(rawValue: d.string(forKey: "edge") ?? "") ?? .right
        dockStyle = DockStyle(rawValue: d.string(forKey: "dockStyle") ?? "") ?? .stripes
        keepOpen = bool("keepOpen", false)
        fanOnClick = bool("fanOnClick", false)
        screenChoice = d.string(forKey: "screens") ?? "main"
        fontSize = d.object(forKey: "fontSize") as? Int ?? 18
        defaultFont = d.string(forKey: "defaultFont") ?? (NSFontManager.shared.availableFontFamilies.contains("Bradley Hand") ? "Bradley Hand" : "")
        activationDelay = d.object(forKey: "activationDelay") as? Double ?? 0.05
        showOverFullScreen = bool("showOverFullScreen", true)
        autoHideToolbar = bool("autoHideToolbar", false)
        emojiButton = bool("emojiButton", true)
        menuBarIcon = bool("menuBarIcon", true)
        customColors = d.stringArray(forKey: "customColors") ?? []
        syncEnabled = bool("syncEnabled", false)
        syncPath = d.string(forKey: "syncPath") ?? SyncEngine.defaultFolder.path
        markdownEnabled = bool("markdownEnabled", false)
        markdownPath = d.string(forKey: "markdownPath") ?? ""
        autoUpdate = bool("autoUpdate", true)
        hotkeys = (d.data(forKey: "hotkeys").flatMap { try? JSONDecoder().decode([String: Hotkey].self, from: $0) }) ?? [:]
    }

    func hotkey(_ action: HotkeyAction) -> Hotkey? {
        if let custom = hotkeys[action.rawValue] { return custom.keyCode < 0 ? nil : custom }
        return action.defaultHotkey
    }

    /// nil efface le raccourci ; `resetHotkey` rend la valeur d'origine.
    func setHotkey(_ action: HotkeyAction, _ hotkey: Hotkey?) {
        hotkeys[action.rawValue] = hotkey ?? Hotkey(keyCode: -1, modifiers: 0)
    }
    func resetHotkey(_ action: HotkeyAction) { hotkeys[action.rawValue] = nil }

    /// Couleurs proposées pour une note : les cinq de base, puis les personnalisées.
    var allColors: [String] { NoteColor.palette.map(\.id) + customColors }
}

extension Color {
    init(noteColor id: String) {
        let c = NoteColor.components(NoteColor.hex(id)) ?? (1, 0.9, 0.5)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }
}

extension NSColor {
    convenience init(noteColor id: String) {
        let c = NoteColor.components(NoteColor.hex(id)) ?? (1, 0.9, 0.5)
        self.init(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
}

import AppKit
import SwiftUI
import mSTICKCore

extension Notification.Name {
    static let prefsChanged = Notification.Name("mSTICKPrefsChanged")
}

/// Apparence des notes : sombre par défaut (comme Notel), clair, ou celle du système.
enum NoteAppearance: String, CaseIterable { case dark, light, auto }

/// Les huit croix de fermeture de Notel.
enum CloseStyle: String, CaseIterable { case classic, chunky, hollow, pixel, crisscross, dot, square, heart }

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
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

    @Published var appearance: NoteAppearance { didSet { d.set(appearance.rawValue, forKey: "appearance"); changed() } }
    @Published var closeStyle: CloseStyle { didSet { d.set(closeStyle.rawValue, forKey: "closeStyle"); changed() } }
    @Published var closeLeft: Bool { didSet { d.set(closeLeft, forKey: "closeLeft"); changed() } }
    @Published var autoStack: Bool { didSet { d.set(autoStack, forKey: "autoStack"); changed() } }
    @Published var smartCalc: Bool { didSet { d.set(smartCalc, forKey: "smartCalc"); changed() } }
    @Published var slashCommands: Bool { didSet { d.set(slashCommands, forKey: "slashCommands"); changed() } }
    @Published var reminders: Bool { didSet { d.set(reminders, forKey: "reminders"); changed() } }
    @Published var defaultFont: String { didSet { d.set(defaultFont, forKey: "defaultFont"); changed() } }
    @Published var fontSize: Int { didSet { d.set(fontSize, forKey: "fontSize"); changed() } }
    @Published var showOverFullScreen: Bool { didSet { d.set(showOverFullScreen, forKey: "showOverFullScreen"); changed() } }
    @Published var menuBarIcon: Bool { didSet { d.set(menuBarIcon, forKey: "menuBarIcon"); changed() } }
    @Published var customColors: [String] { didSet { d.set(customColors, forKey: "customColors"); changed() } }
    @Published var syncEnabled: Bool { didSet { d.set(syncEnabled, forKey: "syncEnabled"); changed() } }
    @Published var syncPath: String { didSet { d.set(syncPath, forKey: "syncPath"); changed() } }
    @Published var markdownEnabled: Bool { didSet { d.set(markdownEnabled, forKey: "markdownEnabled"); changed() } }
    @Published var markdownPath: String { didSet { d.set(markdownPath, forKey: "markdownPath"); changed() } }
    @Published var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "autoUpdate"); changed() } }
    @Published var hotkeys: [String: Hotkey] { didSet { d.set(try? JSONEncoder().encode(hotkeys), forKey: "hotkeys"); changed() } }

    static let fontSizes = [10, 12, 13, 14, 16, 18, 20, 24]

    private init() {
        func bool(_ k: String, _ v: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? v }
        let d = UserDefaults.standard
        appearance = NoteAppearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .dark
        closeStyle = CloseStyle(rawValue: d.string(forKey: "closeStyle") ?? "") ?? .classic
        closeLeft = bool("closeLeft", true)
        autoStack = bool("autoStack", true)
        smartCalc = bool("smartCalc", true)
        slashCommands = bool("slashCommands", true)
        reminders = bool("reminders", true)
        fontSize = d.object(forKey: "fontSize") as? Int ?? 14
        defaultFont = d.string(forKey: "defaultFont") ?? ""
        showOverFullScreen = bool("showOverFullScreen", true)
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

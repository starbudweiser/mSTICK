import Foundation

/// Une note adhésive. Le corps est du Markdown ; le titre et l'emoji sont à part.
public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var emoji: String
    public var body: String
    /// Identifiant de palette (« yellow »…) ou couleur personnalisée « #RRGGBB ».
    public var color: String
    /// Famille de police ; nil = police du système.
    public var font: String?
    public var pinned: Bool
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Rang dans le deck (0 = en haut / à gauche).
    public var order: Int
    /// Visible sur tous les bureaux (nil = non).
    public var allDesktops: Bool?
    /// Collée au bureau : derrière les fenêtres des autres applis (nil = non).
    public var glued: Bool?
    /// Rappels posés dans le texte (« remind me tomorrow at 8pm… »).
    public var reminders: [NoteReminder]?

    public init(id: UUID = UUID(), title: String = "", emoji: String = "", body: String = "", color: String = "yellow",
                font: String? = nil, pinned: Bool = false, archived: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date(), order: Int = 0) {
        self.id = id; self.title = title; self.emoji = emoji; self.body = body; self.color = color; self.font = font
        self.pinned = pinned; self.archived = archived; self.createdAt = createdAt; self.updatedAt = updatedAt; self.order = order
    }

    /// Titre affiché : le titre, sinon la première ligne du corps, sinon « Sans titre » fourni par l'appelant.
    public func displayTitle(fallback: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let first = body.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#-*[] \t")) } ?? ""
        return first.isEmpty ? fallback : String(first.prefix(40))
    }
}

/// Couleurs de base d'une note et lecture des couleurs personnalisées.
public enum NoteColor {
    public static let palette: [(id: String, hex: String)] = [
        ("yellow", "#F8D872"), ("pink", "#F5A9A2"), ("green", "#A8E4C4"), ("blue", "#A9CBF8"), ("purple", "#CFC0F5"),
        ("teal", "#8EDAD8"), ("orange", "#F6B684"),
    ]

    /// Mélange deux couleurs (t = part de `b`).
    public static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        guard let x = components(a), let y = components(b) else { return a }
        func c(_ u: Double, _ v: Double) -> Int { Int(((u + (v - u) * t) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(x.red, y.red), c(x.green, y.green), c(x.blue, y.blue))
    }

    /// Fond d'une note en thème sombre : presque noir, teinté de la couleur de la note (le titre prend la couleur pleine).
    public static func darkBackground(_ color: String) -> String { mix(hex(color), "#0F0F10", 0.88) }

    /// #RRGGBB de la couleur d'une note.
    public static func hex(_ color: String) -> String {
        if color.hasPrefix("#"), components(color) != nil { return color.uppercased() }
        return palette.first { $0.id == color }?.hex ?? palette[0].hex
    }

    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    /// Le fond est clair : le texte doit être foncé.
    public static func isLight(_ hex: String) -> Bool {
        guard let c = components(hex) else { return true }
        return 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue > 0.55
    }
}

/// Raccourci clavier global (code touche + modificateurs au format NSEvent).
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: Int
    public var modifiers: UInt
    public init(keyCode: Int, modifiers: UInt) { self.keyCode = keyCode; self.modifiers = modifiers }

    public static let command: UInt = 1 << 20
    public static let option: UInt = 1 << 19
    public static let control: UInt = 1 << 18
    public static let shift: UInt = 1 << 17
}

/// Actions auxquelles on peut associer un raccourci global.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case newNote, fan, peek, library, hideAll

    public var defaultHotkey: Hotkey {
        let om = Hotkey.option | Hotkey.command
        switch self {
        case .newNote: return Hotkey(keyCode: 45, modifiers: om)       // ⌥⌘N, depuis n'importe quelle appli
        case .fan: return Hotkey(keyCode: 3, modifiers: Hotkey.option)  // ⌥F
        case .peek: return Hotkey(keyCode: 50, modifiers: Hotkey.option) // ⌥`
        case .library: return Hotkey(keyCode: 37, modifiers: om)       // ⌥⌘L
        case .hideAll: return Hotkey(keyCode: 4, modifiers: Hotkey.control | om) // ⌃⌥⌘H
        }
    }
}

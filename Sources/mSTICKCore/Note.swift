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
        ("yellow", "#FFE680"), ("pink", "#FFB8D1"), ("green", "#B8E6A8"), ("blue", "#A8D4FF"), ("purple", "#D4B8FF"),
    ]

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
    case newNote, reopenLast, allNotes, archive, moveDeck, hideAll

    public var defaultHotkey: Hotkey {
        let om = Hotkey.option | Hotkey.command
        switch self {
        case .newNote: return Hotkey(keyCode: 45, modifiers: om)       // N
        case .reopenLast: return Hotkey(keyCode: 31, modifiers: om)    // O
        case .allNotes: return Hotkey(keyCode: 37, modifiers: om)      // L
        case .archive: return Hotkey(keyCode: 0, modifiers: om)        // A
        case .moveDeck: return Hotkey(keyCode: 14, modifiers: om)      // E
        case .hideAll: return Hotkey(keyCode: 4, modifiers: Hotkey.control | om) // H
        }
    }
}

public enum DeckEdge: String, CaseIterable, Codable, Sendable {
    case right, left, bottom, top
    public var next: DeckEdge {
        switch self { case .right: return .bottom; case .bottom: return .left; case .left: return .top; case .top: return .right }
    }
    /// Le deck est une colonne (bord gauche ou droit) ; sinon une rangée.
    public var isVertical: Bool { self == .left || self == .right }
}

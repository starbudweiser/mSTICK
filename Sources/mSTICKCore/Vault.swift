import CryptoKit
import Foundation
import Security

/// Clé AES-256 des notes : Trousseau de connexion, sur cet appareil seulement.
public enum VaultKey {
    public static func load(service: String, fileOverride: URL? = nil) throws -> SymmetricKey {
        if let fileOverride { return try fileKey(fileOverride) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "notes-key", kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 { return SymmetricKey(data: data) }
        if status != errSecItemNotFound && status != errSecSuccess { throw VaultError.keychain(status) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "notes-key", kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw VaultError.keychain(added) }
        return key
    }

    private static func fileKey(_ url: URL) throws -> SymmetricKey {
        if let data = try? Data(contentsOf: url), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try key.withUnsafeBytes { Data($0) }.write(to: url, options: .atomic)
        return key
    }
}

public enum VaultError: Error { case keychain(OSStatus), corrupt }

/// Stockage local : un fichier chiffré (AES-GCM) par note, plus un marqueur de suppression par note effacée.
public final class Vault {
    public let directory: URL
    private let key: SymmetricKey
    private let fm = FileManager.default
    private var notesDir: URL { directory.appendingPathComponent("notes", isDirectory: true) }
    private var deletedDir: URL { directory.appendingPathComponent("deleted", isDirectory: true) }

    public static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["MSTICK_DATA_DIR"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mSTICK", isDirectory: true)
    }

    public init(directory: URL, key: SymmetricKey) throws {
        self.directory = directory; self.key = key
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: deletedDir, withIntermediateDirectories: true)
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public func seal(_ note: Note) throws -> Data {
        let box = try AES.GCM.seal(Self.encoder.encode(note), using: key)
        guard let combined = box.combined else { throw VaultError.corrupt }
        return combined
    }

    public func open(_ data: Data) throws -> Note {
        try Self.decoder.decode(Note.self, from: AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key))
    }

    public func loadAll() -> (notes: [Note], deleted: [UUID: Date]) {
        var notes: [Note] = []
        for url in (try? fm.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "note" {
            if let data = try? Data(contentsOf: url), let note = try? open(data) { notes.append(note) }
        }
        var deleted: [UUID: Date] = [:]
        for url in (try? fm.contentsOfDirectory(at: deletedDir, includingPropertiesForKeys: nil)) ?? [] {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
               let data = try? Data(contentsOf: url), let t = try? Self.decoder.decode(Tombstone.self, from: data) { deleted[id] = t.deletedAt }
        }
        return (notes.sorted { $0.order < $1.order }, deleted)
    }

    public func save(_ note: Note) throws {
        try seal(note).write(to: notesDir.appendingPathComponent("\(note.id.uuidString).note"), options: .atomic)
        try? fm.removeItem(at: deletedDir.appendingPathComponent("\(note.id.uuidString).json"))
    }

    /// Supprime la note et laisse un marqueur daté (la synchro s'en sert pour effacer ailleurs).
    public func delete(_ id: UUID, at date: Date = Date()) throws {
        try? fm.removeItem(at: notesDir.appendingPathComponent("\(id.uuidString).note"))
        try Self.encoder.encode(Tombstone(deletedAt: date)).write(to: deletedDir.appendingPathComponent("\(id.uuidString).json"), options: .atomic)
    }

    public func forgetTombstone(_ id: UUID) {
        try? fm.removeItem(at: deletedDir.appendingPathComponent("\(id.uuidString).json"))
    }

    struct Tombstone: Codable { var deletedAt: Date }
}

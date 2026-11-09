import CryptoKit
import XCTest
@testable import mSTICKCore

final class CoreTests: XCTestCase {
    func tmp() -> URL { let u = FileManager.default.temporaryDirectory.appendingPathComponent("mstick-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }

    func testVaultRoundTripAndEncryption() throws {
        let dir = tmp()
        let vault = try Vault(directory: dir, key: SymmetricKey(size: .bits256))
        let note = Note(title: "Courses", body: "secret-body", color: "blue")
        try vault.save(note)
        let file = try Data(contentsOf: dir.appendingPathComponent("notes/\(note.id.uuidString).note"))
        XCTAssertNil(String(data: file, encoding: .utf8)?.range(of: "secret-body"))
        XCTAssertEqual(vault.loadAll().notes.first?.body, "secret-body")
        try vault.delete(note.id)
        XCTAssertTrue(vault.loadAll().notes.isEmpty)
        XCTAssertNotNil(vault.loadAll().deleted[note.id])
    }

    func testSyncMergeAndDeletion() throws {
        let folder = tmp()
        var a = Note(title: "A", body: "v1", updatedAt: Date(timeIntervalSince1970: 1000))
        var out = try SyncEngine.run(folder: folder, notes: [a], deleted: [:])
        XCTAssertEqual(out.written, 1)
        // Autre Mac : version plus récente dans le dossier
        var newer = a; newer.body = "v2"; newer.updatedAt = Date(timeIntervalSince1970: 2000)
        _ = try SyncEngine.run(folder: folder, notes: [newer], deleted: [:])
        out = try SyncEngine.run(folder: folder, notes: [a], deleted: [:])
        XCTAssertEqual(out.updates.first?.body, "v2")
        // Effacement ailleurs
        let gone = Date(timeIntervalSince1970: 3000)
        _ = try SyncEngine.run(folder: folder, notes: [], deleted: [a.id: gone])
        a.updatedAt = Date(timeIntervalSince1970: 2000)
        out = try SyncEngine.run(folder: folder, notes: [a], deleted: [:])
        XCTAssertEqual(out.removals, [a.id])
        // Note inconnue en local, présente dans le dossier : importée
        let b = Note(title: "B")
        _ = try SyncEngine.run(folder: folder, notes: [b], deleted: [:])
        out = try SyncEngine.run(folder: folder, notes: [], deleted: [:])
        XCTAssertEqual(out.updates.map(\.id), [b.id])
    }

    func testArchiveRoundTrip() throws {
        let notes = [Note(title: "x", body: "y", color: "#123456")]
        XCTAssertEqual(try Exporter.importArchive(Exporter.archiveData(notes)).first?.color, "#123456")
        XCTAssertThrowsError(try Exporter.importArchive(Data("{}".utf8)))
    }

    func testMirrorOnlyTouchesOwnFiles() throws {
        let folder = tmp()
        try "mine".write(to: folder.appendingPathComponent("autre.md"), atomically: true, encoding: .utf8)
        let n = Note(title: "Idée", body: "texte")
        try Exporter.mirror([n], to: folder)
        try Exporter.mirror([], to: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("autre.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(Exporter.fileName(n, ext: "md")).path))
    }

    func testScanner() {
        let text = "# Titre\n- [ ] à faire\n[x] fait\n**gras** et *ital* ~~barré~~ `code`\nhttps://a.fr/x [lien](https://b.fr)\n| a | b |"
        let spans = MarkdownScanner.scan(text)
        XCTAssertTrue(spans.contains { $0.kind == .heading(1) })
        XCTAssertTrue(spans.contains { $0.kind == .checkbox(false) })
        XCTAssertTrue(spans.contains { $0.kind == .checkbox(true) })
        XCTAssertTrue(spans.contains { $0.kind == .bold })
        XCTAssertTrue(spans.contains { $0.kind == .italic })
        XCTAssertTrue(spans.contains { $0.kind == .strike })
        XCTAssertTrue(spans.contains { $0.kind == .code })
        XCTAssertTrue(spans.contains { $0.kind == .link("https://b.fr") })
        XCTAssertTrue(spans.contains { $0.kind == .link("https://a.fr/x") })
        XCTAssertTrue(spans.contains { $0.kind == .table })
    }

    @MainActor func testStoreCreateDeleteUndo() throws {
        let store = NoteStore(vault: try Vault(directory: tmp(), key: SymmetricKey(size: .bits256)))
        let n = store.create()
        store.update(n.id) { $0.body = "salut" }
        store.flush()
        XCTAssertEqual(store.search("sal", filter: .active).count, 1)
        store.setArchived([n.id], true)
        XCTAssertEqual(store.search("", filter: .active).count, 0)
        let gone = store.delete([n.id])
        XCTAssertTrue(store.notes.isEmpty)
        store.restore(gone)
        XCTAssertEqual(store.notes.count, 1)
    }
}

/// Les 4 langues ont exactement les mêmes clés, et toutes les clés écrites en dur dans le code existent.
final class StringsTests: XCTestCase {
    private func keys(_ lang: String) throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8)
        return Set(text.split(separator: "\n").compactMap { $0.split(separator: "\"", maxSplits: 2, omittingEmptySubsequences: false).dropFirst().first.map(String.init) })
    }

    func testSameKeysInAllLanguages() throws {
        let fr = try keys("fr")
        XCTAssertGreaterThan(fr.count, 100)
        for lang in ["en", "es", "it"] { XCTAssertEqual(try keys(lang), fr, "clés différentes en \(lang)") }
    }
}

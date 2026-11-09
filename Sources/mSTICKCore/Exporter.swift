import Foundation

public enum ExportFormat: String, CaseIterable, Sendable { case markdown, text, single, archive }

public enum ArchiveError: Error { case notAnArchive }

/// Export et import des notes : un fichier par note (.md ou .txt), un fichier unique, ou une archive .stickies réimportable.
public enum Exporter {
    public static func markdown(_ note: Note, fallback: String = "") -> String {
        let head = [note.emoji, note.displayTitle(fallback: fallback)].filter { !$0.isEmpty }.joined(separator: " ")
        return note.body.isEmpty ? "# \(head)\n" : "# \(head)\n\n\(note.body)\n"
    }

    public static func plainText(_ note: Note, fallback: String = "") -> String {
        var body = note.body
        for (pattern, template) in [(#"(?m)^#{1,3}[ \t]+"#, ""), (#"\*\*(.+?)\*\*"#, "$1"), (#"~~(.+?)~~"#, "$1"), (#"</?u>"#, ""),
                                    (#"\[([^\]\n]+)\]\(([^)\s]+)\)"#, "$1 ($2)")] {
            body = body.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        let head = [note.emoji, note.displayTitle(fallback: fallback)].filter { !$0.isEmpty }.joined(separator: " ")
        return body.isEmpty ? head + "\n" : "\(head)\n\n\(body)\n"
    }

    /// Nom de fichier sûr : titre nettoyé + début de l'identifiant (évite les doublons).
    public static func fileName(_ note: Note, ext: String, fallback: String = "note") -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var title = note.displayTitle(fallback: fallback).components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = fallback }
        return "\(String(title.prefix(50))) \(note.id.uuidString.prefix(6)).\(ext)"
    }

    @discardableResult
    public static func export(_ notes: [Note], format: ExportFormat, to directory: URL, fallback: String = "note") throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        switch format {
        case .markdown, .text:
            for note in notes {
                let ext = format == .markdown ? "md" : "txt"
                let url = directory.appendingPathComponent(fileName(note, ext: ext, fallback: fallback))
                let text = format == .markdown ? markdown(note, fallback: fallback) : plainText(note, fallback: fallback)
                try text.write(to: url, atomically: true, encoding: .utf8)
                written.append(url)
            }
        case .single:
            let url = directory.appendingPathComponent("mSTICK.md")
            try notes.map { markdown($0, fallback: fallback) }.joined(separator: "\n---\n\n").write(to: url, atomically: true, encoding: .utf8)
            written.append(url)
        case .archive:
            let url = directory.appendingPathComponent("mSTICK.stickies")
            try archiveData(notes).write(to: url, options: .atomic)
            written.append(url)
        }
        return written
    }

    private struct Archive: Codable { var format: String; var version: Int; var notes: [Note] }

    public static func archiveData(_ notes: [Note]) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(Archive(format: "mstick.stickies", version: 1, notes: notes))
    }

    public static func importArchive(_ data: Data) throws -> [Note] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let archive = try? d.decode(Archive.self, from: data), archive.format == "mstick.stickies" else { throw ArchiveError.notAnArchive }
        return archive.notes
    }

    /// Copie de chaque note en .md dans un dossier (ex. un coffre Obsidian). Seuls les fichiers créés par l'appli sont touchés
    /// (liste tenue dans `.mstick-files.json`).
    public static func mirror(_ notes: [Note], to folder: URL, fallback: String = "note") throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifestURL = folder.appendingPathComponent(".mstick-files.json")
        let previous = ((try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]
        var current: [String: String] = [:]
        for note in notes {
            let name = fileName(note, ext: "md", fallback: fallback)
            current[note.id.uuidString] = name
            let text = markdown(note, fallback: fallback)
            let url = folder.appendingPathComponent(name)
            if (try? String(contentsOf: url, encoding: .utf8)) != text { try text.write(to: url, atomically: true, encoding: .utf8) }
            if let old = previous[note.id.uuidString], old != name { try? fm.removeItem(at: folder.appendingPathComponent(old)) }
        }
        for (id, name) in previous where current[id] == nil { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
        try JSONEncoder().encode(current).write(to: manifestURL, options: .atomic)
    }
}

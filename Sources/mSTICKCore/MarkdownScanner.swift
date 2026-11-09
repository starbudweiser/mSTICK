import Foundation

/// Repère la syntaxe Markdown d'une note (sans la modifier) : l'éditeur s'en sert pour la mise en forme en direct.
public struct MDSpan: Equatable {
    public enum Kind: Equatable {
        case heading(Int), bold, italic, underline, strike, code, link(String), marker, bullet, number, checkbox(Bool), table, quote
    }
    public var range: NSRange
    public var kind: Kind
}

public enum MarkdownScanner {
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let heading = re(#"^(#{1,3})[ \t]+"#)
    private static let checkbox = re(#"^([ \t]*(?:[-*][ \t]+)?)(\[[ xX]?\])(?=[ \t]|$)"#)
    private static let bullet = re(#"^[ \t]*([-*])[ \t]+"#)
    private static let number = re(#"^[ \t]*(\d+\.)[ \t]+"#)
    private static let quote = re(#"^[ \t]*(>)[ \t]?"#)
    private static let boldRE = re(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
    private static let italicStar = re(#"(?<![*\\])\*(?![*\s])(.+?)(?<![*\s])\*(?!\*)"#)
    private static let italicUnder = re(#"(?<![A-Za-z0-9_])_(?![_\s])(.+?)(?<![_\s])_(?![A-Za-z0-9_])"#)
    private static let strikeRE = re(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let underlineRE = re(#"<u>(.+?)</u>"#)
    private static let codeRE = re(#"`([^`\n]+)`"#)
    private static let linkRE = re(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let urlRE = re(#"https?://[^\s)>\]]+"#)

    public static func scan(_ text: String) -> [MDSpan] {
        let ns = text as NSString
        var spans: [MDSpan] = []
        var location = 0
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            var content = line
            while content.length > 0, let c = Optional(ns.character(at: content.location + content.length - 1)), c == 10 || c == 13 { content.length -= 1 }
            scanLine(ns, content, &spans)
            location = line.location + max(line.length, 1)
        }
        return spans
    }

    private static func scanLine(_ ns: NSString, _ line: NSRange, _ spans: inout [MDSpan]) {
        guard line.length > 0 else { return }
        let s = ns.substring(with: line)
        let local = NSRange(location: 0, length: line.length)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + line.location, length: r.length) }

        if s.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            spans.append(MDSpan(range: line, kind: .table))
            for (i, ch) in s.utf16.enumerated() where ch == 124 { spans.append(MDSpan(range: shift(NSRange(location: i, length: 1)), kind: .marker)) }
            return
        }
        if let m = heading.firstMatch(in: s, range: local) {
            spans.append(MDSpan(range: line, kind: .heading(m.range(at: 1).length)))
            spans.append(MDSpan(range: shift(m.range), kind: .marker))
        } else if let m = checkbox.firstMatch(in: s, range: local) {
            let box = m.range(at: 2)
            let checked = (s as NSString).substring(with: box).lowercased().contains("x")
            spans.append(MDSpan(range: shift(box), kind: .checkbox(checked)))
            if checked { spans.append(MDSpan(range: shift(NSRange(location: m.range.length, length: max(0, line.length - m.range.length))), kind: .strike)) }
            let lead = m.range(at: 1)
            if lead.length > 0 { spans.append(MDSpan(range: shift(lead), kind: .marker)) }
        } else if let m = bullet.firstMatch(in: s, range: local) {
            spans.append(MDSpan(range: shift(m.range(at: 1)), kind: .bullet))
        } else if let m = number.firstMatch(in: s, range: local) {
            spans.append(MDSpan(range: shift(m.range(at: 1)), kind: .number))
        } else if let m = quote.firstMatch(in: s, range: local) {
            spans.append(MDSpan(range: shift(m.range), kind: .marker))
            spans.append(MDSpan(range: line, kind: .quote))
        }

        // Code d'abord : ce qui est dedans n'est plus interprété.
        var codeRanges: [NSRange] = []
        for m in codeRE.matches(in: s, range: local) {
            codeRanges.append(m.range)
            spans.append(MDSpan(range: shift(m.range), kind: .code))
            spans.append(MDSpan(range: shift(NSRange(location: m.range.location, length: 1)), kind: .marker))
            spans.append(MDSpan(range: shift(NSRange(location: m.range.location + m.range.length - 1, length: 1)), kind: .marker))
        }
        func free(_ r: NSRange) -> Bool { !codeRanges.contains { NSIntersectionRange($0, r).length > 0 } }

        func pairs(_ regex: NSRegularExpression, open: Int, close: Int, kind: MDSpan.Kind) {
            for m in regex.matches(in: s, range: local) where free(m.range) {
                spans.append(MDSpan(range: shift(m.range(at: 1)), kind: kind))
                spans.append(MDSpan(range: shift(NSRange(location: m.range.location, length: open)), kind: .marker))
                spans.append(MDSpan(range: shift(NSRange(location: m.range.location + m.range.length - close, length: close)), kind: .marker))
            }
        }
        pairs(boldRE, open: 2, close: 2, kind: .bold)
        pairs(italicStar, open: 1, close: 1, kind: .italic)
        pairs(italicUnder, open: 1, close: 1, kind: .italic)
        pairs(strikeRE, open: 2, close: 2, kind: .strike)
        pairs(underlineRE, open: 3, close: 4, kind: .underline)

        var linked: [NSRange] = []
        for m in linkRE.matches(in: s, range: local) where free(m.range) {
            let url = (s as NSString).substring(with: m.range(at: 2))
            linked.append(m.range)
            spans.append(MDSpan(range: shift(m.range(at: 1)), kind: .link(url)))
            spans.append(MDSpan(range: shift(NSRange(location: m.range.location, length: 1)), kind: .marker))
            let tailStart = m.range(at: 1).location + m.range(at: 1).length
            spans.append(MDSpan(range: shift(NSRange(location: tailStart, length: m.range.location + m.range.length - tailStart)), kind: .marker))
        }
        for m in urlRE.matches(in: s, range: local) where free(m.range) && !linked.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            spans.append(MDSpan(range: shift(m.range), kind: .link((s as NSString).substring(with: m.range))))
        }
    }
}

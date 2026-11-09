import AppKit
import mSTICKCore

/// Éditeur Markdown d'une note : le texte reste du Markdown, mis en forme en direct (marques atténuées).
final class StickTextView: NSTextView {
    var fontFamily: String? { didSet { restyle() } }
    var fontSize: CGFloat = 14 { didSet { restyle() } }
    var textTone: NSColor = NSColor(white: 0.12, alpha: 1) { didSet { restyle() } }
    var onCancel: (() -> Void)?
    private(set) var spans: [MDSpan] = []

    func baseFont(bold: Bool = false, italic: Bool = false, mono: Bool = false, size: CGFloat? = nil) -> NSFont {
        let s = size ?? fontSize
        var font: NSFont
        if mono { font = NSFont.monospacedSystemFont(ofSize: s, weight: bold ? .bold : .regular) }
        else if let family = fontFamily, let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: s) { font = f }
        else { font = NSFont.systemFont(ofSize: s) }
        let fm = NSFontManager.shared
        if bold { font = fm.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = fm.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    /// Reprend les attributs de tout le texte d'après le Markdown.
    func restyle() {
        guard let storage = textStorage else { return }
        let text = string
        let full = NSRange(location: 0, length: storage.length)
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3
        let dim = textTone.withAlphaComponent(0.38)
        storage.beginEditing()
        storage.setAttributes([.font: baseFont(), .foregroundColor: textTone, .paragraphStyle: para], range: full)
        spans = MarkdownScanner.scan(text)
        func bump(_ range: NSRange, _ change: (NSFont) -> NSFont) {
            storage.enumerateAttribute(.font, in: range) { value, r, _ in
                if let f = value as? NSFont { storage.addAttribute(.font, value: change(f), range: r) }
            }
        }
        let fm = NSFontManager.shared
        for span in spans where NSMaxRange(span.range) <= storage.length {
            let r = span.range
            switch span.kind {
            case .heading(let level):
                let scale: CGFloat = [1.5, 1.3, 1.15][min(level, 3) - 1]
                storage.addAttribute(.font, value: baseFont(bold: true, size: fontSize * scale), range: r)
            case .bold: bump(r) { fm.convert($0, toHaveTrait: .boldFontMask) }
            case .italic: bump(r) { fm.convert($0, toHaveTrait: .italicFontMask) }
            case .underline: storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                storage.addAttribute(.foregroundColor, value: dim, range: r)
            case .code:
                storage.addAttributes([.font: baseFont(mono: true, size: fontSize * 0.92), .backgroundColor: textTone.withAlphaComponent(0.08)], range: r)
            case .link(let url):
                storage.addAttributes([.foregroundColor: NSColor(red: 0.05, green: 0.30, blue: 0.75, alpha: 1), .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .toolTip: url], range: r)
            case .marker: storage.addAttribute(.foregroundColor, value: dim, range: r)
            case .bullet, .number: storage.addAttribute(.foregroundColor, value: textTone.withAlphaComponent(0.6), range: r)
            case .checkbox(let on):
                storage.addAttributes([.foregroundColor: on ? dim : NSColor(red: 0.05, green: 0.30, blue: 0.75, alpha: 1), .font: baseFont(bold: true, mono: true)], range: r)
            case .table: storage.addAttribute(.font, value: baseFont(mono: true, size: fontSize * 0.92), range: r)
            case .quote: storage.addAttribute(.foregroundColor, value: textTone.withAlphaComponent(0.7), range: r)
            }
        }
        storage.endEditing()
        typingAttributes = [.font: baseFont(), .foregroundColor: textTone, .paragraphStyle: para]
    }

    // MARK: Saisie

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func insertNewline(_ sender: Any?) {
        // Liste en cours : on continue la puce, la numérotation ou la case ; une ligne vide la termine.
        let ns = string as NSString
        let caret = selectedRange().location
        let line = ns.lineRange(for: NSRange(location: min(caret, ns.length), length: 0))
        let text = ns.substring(with: line).trimmingCharacters(in: .newlines)
        let patterns: [(String, (NSTextCheckingResult, NSString) -> String)] = [
            (#"^([ \t]*)([-*])[ \t]+\[[ xX]?\][ \t]+"#, { m, s in s.substring(with: m.range(at: 1)) + "- [ ] " }),
            (#"^([ \t]*)\[[ xX]?\][ \t]+"#, { m, s in s.substring(with: m.range(at: 1)) + "[ ] " }),
            (#"^([ \t]*)([-*])[ \t]+"#, { m, s in s.substring(with: m.range(at: 1)) + s.substring(with: m.range(at: 2)) + " " }),
            (#"^([ \t]*)(\d+)\.[ \t]+"#, { m, s in s.substring(with: m.range(at: 1)) + "\((Int(s.substring(with: m.range(at: 2))) ?? 0) + 1). " }),
        ]
        let t = text as NSString
        for (pattern, make) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: text, range: NSRange(location: 0, length: t.length)) else { continue }
            if m.range.length == t.length { // puce vide : on sort de la liste
                let r = NSRange(location: line.location, length: t.length)
                if shouldChangeText(in: r, replacementString: "") { replaceCharacters(in: r, with: ""); didChangeText() }
                return
            }
            insertText("\n" + make(m, t), replacementRange: selectedRange())
            return
        }
        super.insertNewline(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer {
            let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            var fraction: CGFloat = 0
            let index = lm.characterIndex(for: p, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
            let glyph = lm.glyphIndex(for: p, in: tc)
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
            if rect.contains(p) {
                for span in spans where NSLocationInRange(index, span.range) {
                    if case .checkbox(let on) = span.kind { toggleCheckbox(span.range, on: on); return }
                    if case .link(let url) = span.kind, !event.modifierFlags.contains(.option) {
                        if let u = URL(string: url) ?? URL(string: "https://" + url) { NSWorkspace.shared.open(u) }
                        return
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(_ range: NSRange, on: Bool) {
        let replacement = on ? "[ ]" : "[x]"
        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
    }

    // MARK: Mise en forme (boutons et raccourcis)

    func toggleWrap(_ open: String, _ close: String? = nil) {
        let close = close ?? open
        let ns = string as NSString
        let sel = selectedRange()
        let before = sel.location >= open.utf16.count ? ns.substring(with: NSRange(location: sel.location - open.utf16.count, length: open.utf16.count)) : ""
        let afterStart = sel.location + sel.length
        let after = afterStart + close.utf16.count <= ns.length ? ns.substring(with: NSRange(location: afterStart, length: close.utf16.count)) : ""
        if before == open, after == close { // déjà entouré : on retire les marques
            let whole = NSRange(location: sel.location - open.utf16.count, length: sel.length + open.utf16.count + close.utf16.count)
            let inner = ns.substring(with: sel)
            if shouldChangeText(in: whole, replacementString: inner) {
                replaceCharacters(in: whole, with: inner); didChangeText()
                setSelectedRange(NSRange(location: whole.location, length: sel.length))
            }
            return
        }
        let inner = ns.substring(with: sel)
        let text = open + inner + close
        if shouldChangeText(in: sel, replacementString: text) {
            replaceCharacters(in: sel, with: text); didChangeText()
            setSelectedRange(NSRange(location: sel.location + open.utf16.count, length: sel.length))
        }
    }

    /// Ajoute, remplace ou retire un préfixe de ligne (« # », « - », « - [ ] »…) sur les lignes sélectionnées.
    func togglePrefix(_ prefix: String, replacing pattern: String = #"^(#{1,3}[ \t]+|[-*][ \t]+\[[ xX]?\][ \t]+|[-*][ \t]+|\d+\.[ \t]+)"#) {
        let ns = string as NSString
        let lines = ns.lineRange(for: selectedRange())
        let block = ns.substring(with: lines)
        let re = try? NSRegularExpression(pattern: pattern)
        var out: [String] = []
        let parts = block.components(separatedBy: "\n")
        let allHave = parts.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix(prefix) }
        for part in parts {
            if part.isEmpty { out.append(part); continue }
            var line = part
            if let m = re?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                line = (line as NSString).replacingCharacters(in: m.range, with: "")
            }
            out.append(allHave ? line : prefix + line)
        }
        let text = out.joined(separator: "\n")
        if shouldChangeText(in: lines, replacementString: text) {
            replaceCharacters(in: lines, with: text); didChangeText()
            setSelectedRange(NSRange(location: lines.location, length: (text as NSString).length - (text.hasSuffix("\n") ? 1 : 0)))
        }
    }

    func insertLink() {
        let sel = selectedRange()
        let inner = (string as NSString).substring(with: sel)
        let label = inner.isEmpty ? "lien" : inner
        let text = "[\(label)](https://)"
        if shouldChangeText(in: sel, replacementString: text) {
            replaceCharacters(in: sel, with: text); didChangeText()
            setSelectedRange(NSRange(location: sel.location + label.utf16.count + 3, length: 8))
        }
    }
}

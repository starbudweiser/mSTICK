import AppKit
import mSTICKCore

/// Éditeur Markdown d'une note : le texte reste du Markdown, mis en forme en direct (marques atténuées).
final class StickTextView: NSTextView {
    var fontFamily: String? { didSet { restyle() } }
    var fontSize: CGFloat = 14 { didSet { restyle() } }
    var textTone: NSColor = NSColor(white: 0.12, alpha: 1) { didSet { restyle() } }
    var accent: NSColor = NSColor(red: 0.05, green: 0.30, blue: 0.75, alpha: 1) { didSet { restyle() } }
    var calcEnabled = true { didSet { restyle() } }
    var slashEnabled = true
    var remindersEnabled = true
    var onCancel: (() -> Void)?
    var onReminder: ((NoteReminder) -> Void)?
    var onCommand: ((String) -> Void)?
    private(set) var spans: [MDSpan] = []
    private(set) var calc: [Int: String] = [:]

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
                storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .toolTip: url], range: r)
            case .marker: storage.addAttribute(.foregroundColor, value: dim, range: r)
            case .bullet, .number: storage.addAttribute(.foregroundColor, value: textTone.withAlphaComponent(0.6), range: r)
            case .checkbox(let on):
                storage.addAttributes([.foregroundColor: on ? dim : accent, .font: baseFont(bold: true, mono: true)], range: r)
            case .table: storage.addAttribute(.font, value: baseFont(mono: true, size: fontSize * 0.92), range: r)
            case .quote: storage.addAttribute(.foregroundColor, value: textTone.withAlphaComponent(0.7), range: r)
            }
        }
        // Lignes de rappel (« 🔔 demain · 20:00 · … ») en couleur de la note.
        let ns = text as NSString
        var loc = 0
        while loc < ns.length {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            if ns.substring(with: line).hasPrefix("🔔") { storage.addAttribute(.foregroundColor, value: accent, range: line) }
            loc = NSMaxRange(line)
        }
        storage.endEditing()
        calc = calcEnabled ? SmartCalc.evaluate(text) : [:]
        needsDisplay = true
        typingAttributes = [.font: baseFont(), .foregroundColor: textTone, .paragraphStyle: para]
    }

    // MARK: Saisie

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func insertNewline(_ sender: Any?) {
        if handleSmartLine() { return }
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


// MARK: Smart Calc (filigrane), rappels

extension StickTextView {
    /// Début de chaque ligne (en UTF-16), dans l'ordre.
    private func lineRanges() -> [NSRange] {
        let ns = string as NSString
        var out: [NSRange] = []
        var loc = 0
        while loc <= ns.length {
            let r = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
            var content = r
            while content.length > 0, [10, 13].contains(ns.character(at: content.location + content.length - 1)) { content.length -= 1 }
            out.append(content)
            if NSMaxRange(r) >= ns.length { if ns.length > 0, [10, 13].contains(ns.character(at: ns.length - 1)) { out.append(NSRange(location: ns.length, length: 0)) }; break }
            loc = NSMaxRange(r)
        }
        return out
    }

    /// Au retour chariot : « 567+45 = » reçoit son résultat ; « remind me … » devient un rappel. Renvoie vrai si la ligne est traitée.
    func handleSmartLine() -> Bool {
        let ns = string as NSString
        let caret = selectedRange().location
        guard selectedRange().length == 0 else { return false }
        let lines = lineRanges()
        guard let index = lines.firstIndex(where: { caret >= $0.location && caret <= NSMaxRange($0) }) else { return false }
        let line = lines[index]
        guard caret == NSMaxRange(line) else { return false }
        let text = ns.substring(with: line)
        if calcEnabled, let result = SmartCalc.resultIfTrailingEquals(string, line: index) {
            let r = NSRange(location: caret, length: 0)
            if shouldChangeText(in: r, replacementString: " " + result) { replaceCharacters(in: r, with: " " + result); didChangeText() }
            return false // puis le retour chariot normal
        }
        if remindersEnabled, let parsed = ReminderParser.parse(text) {
            let label = ReminderParser.label(for: parsed)
            if shouldChangeText(in: line, replacementString: label) { replaceCharacters(in: line, with: label); didChangeText() }
            onReminder?(NoteReminder(date: parsed.date, label: label))
            setSelectedRange(NSRange(location: line.location + (label as NSString).length, length: 0))
            return false
        }
        return false
    }

    /// Résultat des calculs, dessiné après la fin de la ligne sans toucher au texte.
    func drawCalc() {
        guard calcEnabled, !calc.isEmpty, let lm = layoutManager, let tc = textContainer else { return }
        let lines = lineRanges()
        let attrs: [NSAttributedString.Key: Any] = [.font: baseFont(mono: true, size: fontSize * 0.88), .foregroundColor: accent.withAlphaComponent(0.85)]
        lm.ensureLayout(for: tc)
        for (i, result) in calc {
            guard lines.indices.contains(i), lines[i].length > 0 else { continue }
            let glyph = lm.glyphRange(forCharacterRange: NSRange(location: NSMaxRange(lines[i]) - 1, length: 1), actualCharacterRange: nil)
            let used = lm.lineFragmentUsedRect(forGlyphAt: glyph.location, effectiveRange: nil)
            let text = "→ " + result
            let size = (text as NSString).size(withAttributes: attrs)
            var x = used.maxX + textContainerOrigin.x + 10
            if x + size.width > bounds.width - 6 { x = max(textContainerOrigin.x, bounds.width - size.width - 6) } // trop long : serré contre le bord
            (text as NSString).draw(at: NSPoint(x: x, y: used.minY + textContainerOrigin.y + (used.height - size.height) / 2), withAttributes: attrs)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCalc()
    }
}

// MARK: Commandes « / »

struct SlashCommand {
    let id: String
    var name: String { L("slash." + id) }
    static let all: [SlashCommand] = ["checklist", "bullets", "numbers", "heading", "quote", "table", "divider", "code", "date", "time", "link", "reminder",
                                      "float", "glue", "desktops", "color", "archive", "delete", "close", "new", "library", "settings"].map { SlashCommand(id: $0) }
}

extension StickTextView {
    /// De la barre oblique (en début de ligne ou après un espace) jusqu'au curseur.
    override var rangeForUserCompletion: NSRange {
        guard slashEnabled else { return super.rangeForUserCompletion }
        let ns = string as NSString
        let caret = selectedRange().location
        var i = caret
        while i > 0 {
            let c = ns.character(at: i - 1)
            if c == 47 { // "/"
                if i - 1 == 0 || [32, 10, 9].contains(ns.character(at: i - 2)) { return NSRange(location: i - 1, length: caret - (i - 1)) }
                break
            }
            if c == 32 || c == 10 || c == 9 { break }
            i -= 1
        }
        return super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let partial = (string as NSString).substring(with: charRange)
        guard slashEnabled, partial.hasPrefix("/") else { return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index) }
        let q = partial.dropFirst().lowercased()
        let list = SlashCommand.all.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.id.contains(q) }
        index.pointee = 0
        return list.map { "/" + $0.name }
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        guard word.hasPrefix("/"), slashEnabled else { super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag); return }
        guard flag, movement == NSTextMovement.return.rawValue || movement == NSTextMovement.tab.rawValue,
              let cmd = SlashCommand.all.first(where: { "/" + $0.name == word }) else { return }
        perform(slash: cmd.id, replacing: charRange)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard slashEnabled, (string as? String)?.count == 1 else { return }
        let r = rangeForUserCompletion
        if r.length > 0, (self.string as NSString).substring(with: r).hasPrefix("/") { DispatchQueue.main.async { [weak self] in self?.complete(nil) } }
    }

    /// Exécute une commande : le texte à insérer est du Markdown ; le reste passe à la fenêtre (`onCommand`).
    func perform(slash id: String, replacing range: NSRange) {
        func put(_ text: String, caret: Int? = nil) {
            if shouldChangeText(in: range, replacementString: text) {
                replaceCharacters(in: range, with: text); didChangeText()
                setSelectedRange(NSRange(location: range.location + (caret ?? (text as NSString).length), length: 0))
            }
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        let tf = DateFormatter(); tf.dateStyle = .none; tf.timeStyle = .short
        switch id {
        case "checklist": put("- [ ] ")
        case "bullets": put("- ")
        case "numbers": put("1. ")
        case "heading": put("# ")
        case "quote": put("> ")
        case "table": let t = "| A | B |\n| --- | --- |\n|  |  |"; put(t, caret: (t as NSString).length - 4)
        case "divider": put("---\n")
        case "code": put("```\n\n```", caret: 4)
        case "date": put(df.string(from: Date()))
        case "time": put(tf.string(from: Date()))
        case "link": put("[](https://)", caret: 1)
        case "reminder": let t = L("slash.reminder.template"); put(t, caret: (t as NSString).length)
        default:
            put("")
            onCommand?(id)
        }
    }
}

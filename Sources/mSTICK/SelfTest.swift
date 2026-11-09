import AppKit

/// `mSTICK --selftest` : vérifie l'éditeur (listes, mise en forme) sans ouvrir de fenêtre. Code de sortie 1 en cas d'échec.
@MainActor
enum SelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ got: String, _ want: String) {
            if got != want { failures += 1; print("ÉCHEC \(name) : obtenu « \(got.replacingOccurrences(of: "\n", with: "⏎")) », attendu « \(want.replacingOccurrences(of: "\n", with: "⏎")) »") }
            else { print("ok    \(name)") }
        }
        func editor(_ text: String, select: NSRange? = nil) -> StickTextView {
            let tv = StickTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
            tv.isRichText = false; tv.allowsUndo = true
            tv.string = text
            tv.setSelectedRange(select ?? NSRange(location: (text as NSString).length, length: 0))
            return tv
        }
        var tv = editor("- a"); tv.insertNewline(nil); check("puce continue", tv.string, "- a\n- ")
        tv = editor("- a\n- "); tv.insertNewline(nil); check("puce vide termine la liste", tv.string, "- a\n")
        tv = editor("1. x"); tv.insertNewline(nil); check("numérotation continue", tv.string, "1. x\n2. ")
        tv = editor("- [ ] t"); tv.insertNewline(nil); check("case continue", tv.string, "- [ ] t\n- [ ] ")
        tv = editor("[x] t"); tv.insertNewline(nil); check("case courte continue", tv.string, "[x] t\n[ ] ")
        tv = editor("plain"); tv.insertNewline(nil); check("ligne simple", tv.string, "plain\n")
        tv = editor("ab", select: NSRange(location: 0, length: 2)); tv.toggleWrap("**"); check("gras ajouté", tv.string, "**ab**")
        tv.toggleWrap("**"); check("gras retiré", tv.string, "ab")
        tv = editor("ab", select: NSRange(location: 0, length: 2)); tv.toggleWrap("<u>", "</u>"); check("souligné", tv.string, "<u>ab</u>")
        tv = editor("a\nb", select: NSRange(location: 0, length: 3)); tv.togglePrefix("- "); check("puces ajoutées", tv.string, "- a\n- b")
        tv.togglePrefix("- "); check("puces retirées", tv.string, "a\nb")
        tv = editor("t", select: NSRange(location: 0, length: 1)); tv.togglePrefix("# "); check("titre", tv.string, "# t")
        tv.togglePrefix("- [ ] "); check("titre remplacé par case", tv.string, "- [ ] t")
        tv = editor("x", select: NSRange(location: 0, length: 1)); tv.insertLink(); check("lien", tv.string, "[x](https://)")
        tv = editor("# T\n**g**"); tv.fontSize = 14; tv.restyle()
        let heading = tv.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        check("titre plus grand", (heading?.pointSize ?? 0) > 14 ? "oui" : "non", "oui")
        print(failures == 0 ? "Tous les essais passent." : "\(failures) échec(s).")
        return failures == 0
    }
}

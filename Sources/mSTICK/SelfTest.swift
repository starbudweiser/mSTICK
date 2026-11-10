import AppKit
import SwiftUI
import CryptoKit
import mSTICKCore

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
        // Commandes « / »
        tv = editor("/che"); tv.perform(slash: "checklist", replacing: NSRange(location: 0, length: 4)); check("/checklist", tv.string, "- [ ] ")
        tv = editor("a /ta"); tv.perform(slash: "table", replacing: NSRange(location: 2, length: 3)); check("/table", tv.string, "a | A | B |\n| --- | --- |\n|  |  |")
        tv = editor("/di"); tv.perform(slash: "divider", replacing: NSRange(location: 0, length: 3)); check("/divider", tv.string, "---\n")
        tv = editor("a /ta"); check("plage de complétion", NSStringFromRange(tv.rangeForUserCompletion), "{2, 3}")
        var idx = 0
        let list = tv.completions(forPartialWordRange: tv.rangeForUserCompletion, indexOfSelectedItem: &idx) ?? []
        check("complétion /ta", list.contains("/" + L("slash.table")) && !list.contains("/" + L("slash.heading")) ? "oui" : "non: \(list)", "oui")
        tv = editor("http://x/y"); check("pas de commande dans une URL", NSStringFromRange(tv.rangeForUserCompletion) == "{2, 0}" ? "faux" : "ok", "ok")
        let fan = FanModel(); fan.notes = [Note(), Note(), Note()]; fan.move(5); check("Fan : borne haute", String(fan.index), "2"); fan.move(-9); check("Fan : borne basse", String(fan.index), "0")
        // Smart Calc et rappels au retour chariot
        tv = editor("567+45 ="); tv.insertNewline(nil); check("calcul inséré", tv.string, "567+45 = 612\n")
        tv = editor("remind me tomorrow at 8pm to call"); var got: NoteReminder?; tv.onReminder = { got = $0 }; tv.insertNewline(nil)
        check("rappel créé", got != nil && tv.string.hasPrefix("🔔") && tv.string.hasSuffix("call\n") ? "oui" : "non: \(tv.string)", "oui")
        print(failures == 0 ? "Tous les essais passent." : "\(failures) échec(s).")
        return failures == 0
    }
}

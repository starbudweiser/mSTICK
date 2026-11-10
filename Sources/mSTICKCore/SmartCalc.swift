import Foundation

/// Smart Calc : calculs en fin de ligne avec valeurs nommées (« price = $129 », « sale price = price - discount »).
/// Le texte n'est jamais modifié : on rend le résultat à afficher en filigrane, ligne par ligne.
public enum SmartCalc {
    struct Val {
        var n: Double
        var pct = false
        var cur: String?
    }

    /// Un résultat par ligne qui en mérite un : (index de ligne depuis 0) → texte « 94.17 » ou « $94.17 ».
    public static func evaluate(_ text: String) -> [Int: String] {
        var vars: [String: Val] = [:]
        var out: [Int: String] = [:]
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            if let (value, show) = line(raw, vars: &vars), show { out[i] = format(value) }
        }
        return out
    }

    /// La valeur d'une ligne qui se termine par « = » (pour l'insérer au retour chariot).
    public static func resultIfTrailingEquals(_ text: String, line index: Int) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(index), lines[index].trimmingCharacters(in: .whitespaces).hasSuffix("=") else { return nil }
        return evaluate(text)[index]
    }

    // MARK: Ligne

    private static func line(_ raw: String, vars: inout [String: Val]) -> (Val, Bool)? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.contains(where: \.isNumber) || s.contains("=") else { return nil }
        if let eq = s.firstIndex(of: "=") {
            let lhs = String(s[..<eq]).trimmingCharacters(in: .whitespaces)
            let rhs = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if isName(lhs) {
                var p = Parser(chars: Array(rhs), vars: vars)
                guard let v = p.parse() else { return nil }
                vars[normalize(lhs)] = v
                return (v, p.sawOperation && !rhs.isEmpty)
            }
            var p = Parser(chars: Array(lhs), vars: vars)
            guard let v = p.parse() else { return nil }
            return (v, rhs.isEmpty) // « 567+45 = » : on propose le résultat ; « 567+45 = 612 » est déjà complet
        }
        var p = Parser(chars: Array(s), vars: vars)
        guard let v = p.parse() else { return nil }
        return (v, false)
    }

    private static func isName(_ s: String) -> Bool {
        guard let f = s.first, f.isLetter else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0 == " " || $0 == "_" }).joined(separator: " ")
    }

    static func format(_ v: Val) -> String {
        if v.pct { return trim(v.n * 100) + "%" }
        let body = trim(v.n)
        switch v.cur {
        case "$"?: return "$" + body
        case "£"?: return "£" + body
        case "€"?: return body + " €"
        default: return body
        }
    }

    private static func trim(_ x: Double) -> String {
        let r = (x * 100).rounded() / 100
        if r == r.rounded() { return String(format: "%.0f", r) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    // MARK: Analyse d'une expression

    struct Parser {
        let chars: [Character]
        let vars: [String: Val]
        var i = 0
        var sawOperation = false
        var failed = false

        init(chars: [Character], vars: [String: Val]) { self.chars = chars; self.vars = vars }

        mutating func parse() -> Val? {
            let v = expr()
            skipSpaces()
            return failed || i < chars.count ? nil : v
        }

        mutating func skipSpaces() { while i < chars.count, chars[i] == " " { i += 1 } }

        mutating func expr() -> Val {
            var l = term()
            while !failed {
                skipSpaces()
                guard i < chars.count, chars[i] == "+" || chars[i] == "-" else { break }
                let plus = chars[i] == "+"; i += 1; sawOperation = true
                let r = term()
                if r.pct && !l.pct { l = Val(n: l.n * (1 + (plus ? r.n : -r.n)), cur: l.cur) }
                else { l = Val(n: plus ? l.n + r.n : l.n - r.n, pct: l.pct && r.pct, cur: l.cur ?? r.cur) }
            }
            return l
        }

        mutating func term() -> Val {
            var l = unary()
            while !failed {
                skipSpaces()
                guard i < chars.count else { break }
                let c = chars[i]
                guard c == "*" || c == "/" || c == "×" || c == "÷" || ((c == "x" || c == "X") && !startsName()) else { break }
                i += 1; sawOperation = true
                let r = unary()
                if c == "/" || c == "÷" {
                    if r.n == 0 { failed = true; return l }
                    l = Val(n: l.n / r.n, pct: l.pct && r.pct, cur: l.cur ?? r.cur)
                } else { l = Val(n: l.n * r.n, pct: l.pct && r.pct, cur: l.cur ?? r.cur) }
            }
            return l
        }

        /// « x » suivi d'un chiffre ou d'un espace est une multiplication, pas le début d'un nom.
        func startsName() -> Bool {
            guard i + 1 < chars.count else { return false }
            let n = chars[i + 1]
            return n.isLetter
        }

        mutating func unary() -> Val {
            skipSpaces()
            if i < chars.count, chars[i] == "-" { i += 1; var v = unary(); v.n = -v.n; return v }
            return primary()
        }

        mutating func primary() -> Val {
            skipSpaces()
            guard i < chars.count else { failed = true; return Val(n: 0) }
            var cur: String?
            if "$£€".contains(chars[i]) { cur = String(chars[i]); i += 1 }
            if i < chars.count, chars[i] == "(" {
                i += 1
                var v = expr(); skipSpaces()
                if i < chars.count, chars[i] == ")" { i += 1 } else { failed = true }
                v.cur = v.cur ?? cur; sawOperation = true
                return v
            }
            if i < chars.count, chars[i].isNumber || chars[i] == "." {
                var s = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "_" { if chars[i] != "_" { s.append(chars[i]) }; i += 1 }
                guard let n = Double(s) else { failed = true; return Val(n: 0) }
                var v = Val(n: n, cur: cur)
                if i < chars.count, chars[i] == "%" { i += 1; v.n /= 100; v.pct = true }
                else if i < chars.count, "$£€".contains(chars[i]) { v.cur = String(chars[i]); i += 1 }
                return v
            }
            if i < chars.count, chars[i].isLetter {
                let rest = String(chars[i...]).lowercased()
                for name in vars.keys.sorted(by: { $0.count > $1.count }) where rest.hasPrefix(name) {
                    let end = rest.index(rest.startIndex, offsetBy: name.count)
                    if end == rest.endIndex || !(rest[end].isLetter || rest[end].isNumber) {
                        i += name.count; sawOperation = true
                        var v = vars[name]!; v.cur = v.cur ?? cur
                        return v
                    }
                }
            }
            failed = true
            return Val(n: 0)
        }
    }
}

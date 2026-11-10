import Foundation

/// Un rappel posé dans une note (« remind me tomorrow at 8pm to … »).
public struct NoteReminder: Codable, Equatable, Sendable {
    public var date: Date
    /// La ligne telle qu'écrite dans la note (« 🔔 demain · 20:00 · acheter du pain ») : sert à retrouver le rappel si on l'efface.
    public var label: String
    public init(date: Date, label: String) { self.date = date; self.label = label }
}

/// Lit « remind me … » en anglais, français, espagnol ou italien ; sans réseau, sans dépendance à la langue du système.
public enum ReminderParser {
    public struct Parsed: Equatable { public var date: Date; public var text: String }

    private static let triggers = [#"remind\s+me"#, #"rappelle[\s-]+moi"#, #"recu[eé]rdame"#, #"ricordami"#]
    private static let tomorrow = ["tomorrow", "demain", "mañana", "manana", "domani"]
    private static let today = ["today", "tonight", "aujourd'hui", "aujourd’hui", "ce soir", "hoy", "oggi", "stasera"]
    private static let weekdays: [[String]] = [ // dimanche = 1 (Calendar)
        ["sunday", "dimanche", "domingo", "domenica"], ["monday", "lundi", "lunes", "lunedì", "lunedi"], ["tuesday", "mardi", "martes", "martedì", "martedi"],
        ["wednesday", "mercredi", "miércoles", "miercoles", "mercoledì", "mercoledi"], ["thursday", "jeudi", "jueves", "giovedì", "giovedi"],
        ["friday", "vendredi", "viernes", "venerdì", "venerdi"], ["saturday", "samedi", "sábado", "sabado", "sabato"],
    ]

    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
    private static let inRE = re(#"\b(?:in|dans|en|tra|fra)\s+(\d{1,3})\s*(min(?:ute)?s?|h(?:ours?)?|heures?|horas?|ore|ora|days?|jours?|d[ií]as?|giorni)\b"#)
    private static let timeRE = re(#"(\b(?:at|à|a\s+las|alle|all'|@)\s*)?\b(\d{1,2})(?:[:h](\d{2})|h\b)?(?:\s*(a\.?m\.?|p\.?m\.?)(?![\p{L}]))?"#)

    public static func parse(_ line: String, now: Date = Date(), calendar: Calendar = .current) -> Parsed? {
        var rest: String? = nil
        for t in triggers {
            if let m = re(#"^\s*(?:[-*]\s+)?(?:🔔\s*)?"# + t + #"\b[\s,:]*"#).firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                rest = (line as NSString).substring(from: m.range.upperBound); break
            }
        }
        guard var text = rest, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var date: Date?
        var dayGiven = false
        var hour: Int?, minute = 0

        func removeFirst(_ words: [String]) -> Bool {
            let lower = text.lowercased()
            for w in words.sorted(by: { $0.count > $1.count }) {
                let pattern = #"(?<![\p{L}])"# + NSRegularExpression.escapedPattern(for: w) + #"(?![\p{L}])"#
                if let r = lower.range(of: pattern, options: .regularExpression) { text.removeSubrange(r); return true }
            }
            return false
        }

        // « in 2 hours »
        let ns0 = text as NSString
        if let m = inRE.firstMatch(in: text, range: NSRange(location: 0, length: ns0.length)) {
            let n = Int(ns0.substring(with: m.range(at: 1))) ?? 0
            let unit = ns0.substring(with: m.range(at: 2)).lowercased()
            var comp = DateComponents()
            if unit.hasPrefix("min") { comp.minute = n } else if unit.hasPrefix("h") || unit.hasPrefix("hor") || unit.hasPrefix("or") { comp.hour = n } else { comp.day = n }
            date = calendar.date(byAdding: comp, to: now)
            text = ns0.replacingCharacters(in: m.range, with: "")
            return finish(date, text)
        }

        // Heure : « 8:15 », « 8 pm », « at 8 », « à 9h » (un nombre seul n'est pas une heure)
        let ns = text as NSString
        for m in timeRE.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            let hasMinutes = g(3) != nil, ap = g(4)?.lowercased().replacingOccurrences(of: ".", with: ""), hasWord = g(1) != nil
            let whole = ns.substring(with: m.range(at: 0))
            guard hasMinutes || ap != nil || hasWord || whole.lowercased().hasSuffix("h"), var h = Int(g(2) ?? ""), let mm = Int(g(3) ?? "0"), mm < 60 else { continue }
            if ap == "pm", h < 12 { h += 12 }
            if ap == "am", h == 12 { h = 0 }
            guard h < 24 else { continue }
            hour = h; minute = mm
            text = ns.replacingCharacters(in: m.range, with: "")
            break
        }

        // Jour
        var base = calendar.startOfDay(for: now)
        if removeFirst(tomorrow) { base = calendar.date(byAdding: .day, value: 1, to: base)!; dayGiven = true }
        else if removeFirst(today) { dayGiven = true }
        else {
            for (i, names) in weekdays.enumerated() where removeFirst(names) {
                let target = i + 1
                var d = base
                repeat { d = calendar.date(byAdding: .day, value: 1, to: d)! } while calendar.component(.weekday, from: d) != target
                base = d; dayGiven = true; break
            }
        }
        guard dayGiven || hour != nil else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: base)
        comps.hour = hour ?? 9; comps.minute = hour == nil ? 0 : minute
        date = calendar.date(from: comps)
        if !dayGiven, let d = date, d <= now { date = calendar.date(byAdding: .day, value: 1, to: d) } // « remind me at 8am » passé : demain
        return finish(date, text)
    }

    private static func finish(_ date: Date?, _ rawText: String) -> Parsed? {
        guard let date else { return nil }
        var t = rawText.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;-–"))
        t = t.replacingOccurrences(of: #"^(?:to|that|de|d'|d’|que|di|a|para|per)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return Parsed(date: date, text: t)
    }

    /// Ligne écrite dans la note : « 🔔 demain · 20:00 · acheter du pain ».
    public static func label(for p: Parsed, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let day = DateFormatter(); day.locale = locale; day.calendar = calendar; day.dateStyle = .medium; day.timeStyle = .none; day.doesRelativeDateFormatting = true
        let time = DateFormatter(); time.locale = locale; time.calendar = calendar; time.dateStyle = .none; time.timeStyle = .short
        var s = "🔔 \(day.string(from: p.date)) · \(time.string(from: p.date))"
        if !p.text.isEmpty { s += " · \(p.text)" }
        return s
    }
}

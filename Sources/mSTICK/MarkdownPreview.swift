import SwiftUI

/// Rendu simple d'une note Markdown, sans les balises : titres, listes, cases, citations, filets, tableaux, code, gras / italique / lien.
struct MarkdownPreview: View {
    let text: String
    var size: CGFloat = 15
    var family: String? = nil
    var strong: Color = Socle.C.textStrong
    var ink: Color = Socle.C.text
    var muted: Color = Socle.C.textMuted
    var tint: Color = Socle.C.accent
    var line: Color = Socle.C.border

    private enum Block {
        case heading(Int, String), bullet(String, indent: Int), number(String, String), task(Bool, String)
        case quote(String), rule, code(String), table([[String]]), paragraph(String), gap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, b in view(b) }
        }
        .font(f(size, .regular)).foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(_ b: Block) -> some View {
        switch b {
        case .heading(let level, let s):
            inline(s).font(f(size * [1.6, 1.35, 1.15, 1.0][min(level, 4) - 1], .bold)).foregroundStyle(strong).padding(.top, level == 1 ? 6 : 3)
        case .bullet(let s, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•").foregroundStyle(muted); inline(s) }.padding(.leading, CGFloat(indent) * 16)
        case .number(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text(n).foregroundStyle(muted).monospacedDigit(); inline(s) }
        case .task(let done, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? tint : muted)
                inline(s).strikethrough(done).foregroundStyle(done ? muted : ink)
            }
        case .quote(let s):
            HStack(spacing: 10) { Rectangle().fill(line).frame(width: 3); inline(s).foregroundStyle(muted) }
        case .rule: Divider().overlay(line).padding(.vertical, 4)
        case .code(let s):
            Text(s).font(.system(size: size * 0.9, design: .monospaced)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 4))
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell).fontWeight(i == 0 ? .semibold : .regular).padding(.horizontal, 8).padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading).overlay(Rectangle().stroke(line, lineWidth: 0.5))
                        }
                    }
                }
            }
        case .paragraph(let s): inline(s)
        case .gap: Color.clear.frame(height: 4)
        }
    }

    private func f(_ pt: CGFloat, _ w: Font.Weight) -> Font {
        if let family, !family.isEmpty { return .custom(family, size: pt).weight(w) }
        return .system(size: pt, weight: w)
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }

    // MARK: Analyse

    private static func parse(_ text: String) -> [Block] {
        var out: [Block] = []
        var code: [String]? = nil
        var table: [[String]] = []
        func flushTable() { if !table.isEmpty { out.append(.table(table)); table = [] } }
        for raw in text.components(separatedBy: "\n") {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { flushTable(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") {
                let cells = t.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.isEmpty, cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { continue } // ligne « --- | --- »
                table.append(Array(cells)); continue
            }
            flushTable()
            let indent = raw.prefix { $0 == " " }.count / 2
            if t.isEmpty { out.append(.gap) }
            else if t.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { out.append(.rule) }
            else if let m = t.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                out.append(.heading(t[m].filter { $0 == "#" }.count, String(t[m.upperBound...])))
            }
            else if let m = t.range(of: #"^(?:[-*+]\s+)?\[( |x|X)\]\s+"#, options: .regularExpression) {
                out.append(.task(t[m].contains(where: { $0 == "x" || $0 == "X" }), String(t[m.upperBound...])))
            }
            else if let m = t.range(of: #"^[-*+]\s+"#, options: .regularExpression) { out.append(.bullet(String(t[m.upperBound...]), indent: indent)) }
            else if let m = t.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                out.append(.number(String(t[m].trimmingCharacters(in: .whitespaces)), String(t[m.upperBound...])))
            }
            else if t.hasPrefix(">") { out.append(.quote(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))) }
            else { out.append(.paragraph(t)) }
        }
        flushTable()
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        return out
    }
}

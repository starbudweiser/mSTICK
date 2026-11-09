import AppKit
import SwiftUI
import mSTICKCore

@MainActor
final class NoteViewModel: ObservableObject {
    let id: UUID
    let store: NoteStore
    weak var editor: StickTextView?
    @Published var showFormat = false
    @Published var hovering = false
    var onClose: () -> Void = {}
    var onDelete: () -> Void = {}
    init(id: UUID, store: NoteStore) { self.id = id; self.store = store }
}

private let emojiChoices = ["📝", "✅", "🛒", "💡", "📌", "⭐️", "🔥", "📞", "📅", "💼", "🏠", "🎯", "🎵", "🍎", "🚀", "❤️", "📚", "✈️", "💰", "🔑", "⚠️", "❓", "🎁", "🧠", "🛠️", "📷", "🎮", "☕️", "🌱", "🧪"]
private let fontChoices = ["Marker Felt", "Noteworthy", "Chalkboard SE", "Bradley Hand", "Avenir Next", "Georgia", "Menlo", "Inconsolata"]

struct NoteView: View {
    @ObservedObject var vm: NoteViewModel
    @ObservedObject var store: NoteStore
    @ObservedObject var prefs = Prefs.shared
    @State private var options = false
    @State private var emojis = false
    @State private var hoverClose = false

    private var note: Note { store.note(vm.id) ?? Note(id: vm.id) }
    private var hex: String { NoteColor.hex(note.color) }
    private var tone: Color { NoteColor.isLight(hex) ? Color(white: 0.12) : Color(white: 0.95) }
    private var nsTone: NSColor { NoteColor.isLight(hex) ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.95, alpha: 1) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            NoteEditor(text: note.body, family: note.font, size: CGFloat(prefs.fontSize), tone: nsTone,
                       onChange: { text in store.update(vm.id) { $0.body = text } },
                       onCancel: { vm.onClose() },
                       ready: { vm.editor = $0 })
            if !prefs.autoHideToolbar || vm.hovering || vm.showFormat { toolbar }
        }
        .background(Color(noteColor: note.color))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.18), lineWidth: 1))
        .onHover { vm.hovering = $0 }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Button { vm.onClose() } label: {
                ZStack {
                    Circle().fill(Color(red: 0.95, green: 0.36, blue: 0.33)).frame(width: 13, height: 13)
                    if hoverClose { Image(systemName: "xmark").font(.system(size: 7, weight: .black)).foregroundStyle(Color.black.opacity(0.6)) }
                }
            }
            .buttonStyle(.plain).onHover { hoverClose = $0 }.help(L("note.close"))
            if prefs.emojiButton {
                Button { emojis = true } label: {
                    Text(note.emoji.isEmpty ? "☺︎" : note.emoji).font(.system(size: 15)).opacity(note.emoji.isEmpty ? 0.45 : 1).frame(width: 22)
                }
                .buttonStyle(.plain).help(L("note.emoji"))
                .popover(isPresented: $emojis, arrowEdge: .bottom) { emojiGrid }
            }
            TextField(L("note.title.placeholder"), text: Binding(get: { note.title }, set: { t in store.update(vm.id) { $0.title = t } }))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tone)
            Button { store.update(vm.id) { $0.pinned.toggle() } } label: {
                Image(systemName: note.pinned ? "pin.fill" : "pin").font(.system(size: 12)).foregroundStyle(tone.opacity(note.pinned ? 1 : 0.55))
            }
            .buttonStyle(.plain).help(L(note.pinned ? "note.unpin" : "note.pin"))
            Button { options = true } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(tone.opacity(0.7))
            }
            .buttonStyle(.plain).help(L("note.options"))
            .popover(isPresented: $options, arrowEdge: .bottom) { optionsView }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Button { withAnimation(.easeOut(duration: 0.15)) { vm.showFormat.toggle() } } label: {
                Text("Aa").font(.system(size: 13, weight: .bold)).foregroundStyle(tone).frame(width: 30, height: 24)
                    .background(vm.showFormat ? tone.opacity(0.14) : .clear).clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain).help(L("note.format"))
            if vm.showFormat {
                formatButton("bold", L("format.bold")) { vm.editor?.toggleWrap("**") }
                formatButton("italic", L("format.italic")) { vm.editor?.toggleWrap("*") }
                formatButton("underline", L("format.underline")) { vm.editor?.toggleWrap("<u>", "</u>") }
                formatButton("strikethrough", L("format.strike")) { vm.editor?.toggleWrap("~~") }
                formatButton("textformat.size", L("format.heading")) { vm.editor?.togglePrefix("# ") }
                formatButton("list.bullet", L("format.bullets")) { vm.editor?.togglePrefix("- ") }
                formatButton("list.number", L("format.numbers")) { vm.editor?.togglePrefix("1. ") }
                formatButton("checkmark.square", L("format.checks")) { vm.editor?.togglePrefix("- [ ] ") }
                formatButton("link", L("format.link")) { vm.editor?.insertLink() }
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func formatButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tone).frame(width: 26, height: 24)
        }
        .buttonStyle(.plain).help(help)
    }

    private var emojiGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 2), count: 6)
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(emojiChoices, id: \.self) { e in
                    Button { store.update(vm.id) { $0.emoji = e }; emojis = false } label: { Text(e).font(.system(size: 18)) }.buttonStyle(.plain)
                }
            }
            Button(L("note.emoji.none")) { store.update(vm.id) { $0.emoji = "" }; emojis = false }.buttonStyle(.link).font(.system(size: 11))
        }
        .padding(10)
    }

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("note.color")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 8), spacing: 6) {
                ForEach(prefs.allColors, id: \.self) { id in
                    Button { store.update(vm.id) { $0.color = id } } label: {
                        Circle().fill(Color(noteColor: id)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(note.color == id ? Socle.C.accent : Color.black.opacity(0.25), lineWidth: note.color == id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L("note.font")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            Picker("", selection: Binding(get: { note.font ?? "" }, set: { f in store.update(vm.id) { $0.font = f.isEmpty ? nil : f } })) {
                Text(L("note.font.system")).tag("")
                ForEach(fontChoices.filter { NSFontManager.shared.availableFontFamilies.contains($0) }, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 190)
            Divider()
            Button { options = false; store.setArchived([vm.id], !note.archived); vm.onClose() } label: {
                Label(L(note.archived ? "note.unarchive" : "note.archive"), systemImage: note.archived ? "tray.and.arrow.up" : "archivebox")
            }.buttonStyle(.plain)
            Button { options = false; vm.onDelete() } label: {
                Label(L("note.delete"), systemImage: "trash").foregroundStyle(Socle.C.danger)
            }.buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 214, alignment: .leading)
    }
}

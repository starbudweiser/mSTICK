import AppKit
import SwiftUI
import mSTICKCore

/// Le texte suit toujours la largeur visible : jamais de défilement horizontal, même si SwiftUI a d'abord proposé une autre taille.
final class FitScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let doc = documentView, abs(doc.frame.width - contentSize.width) > 0.5 else { return }
        doc.setFrameSize(NSSize(width: contentSize.width, height: doc.frame.height))
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }
}

/// Pont SwiftUI de l'éditeur : le texte vit dans le magasin, l'éditeur ne le réécrit que si une synchro l'a changé.
struct NoteEditor: NSViewRepresentable {
    let text: String
    let family: String?
    let size: CGFloat
    let tone: NSColor
    let accent: NSColor
    let smartCalc: Bool
    let slash: Bool
    let reminders: Bool
    let onChange: (String) -> Void
    let onCancel: () -> Void
    let onReminder: (NoteReminder) -> Void
    let onCommand: (String) -> Void
    let ready: (StickTextView) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FitScrollView()
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let tv = StickTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.textContainerInset = NSSize(width: 12, height: 8)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.insertionPointColor = accent
        tv.delegate = context.coordinator
        tv.onCancel = onCancel
        tv.accent = accent; tv.calcEnabled = smartCalc; tv.slashEnabled = slash; tv.remindersEnabled = reminders
        tv.onReminder = onReminder; tv.onCommand = onCommand
        tv.fontFamily = family; tv.fontSize = size; tv.textTone = tone
        tv.string = text
        tv.restyle()
        scroll.documentView = tv
        context.coordinator.view = tv
        ready(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.view else { return }
        context.coordinator.parent = self
        tv.onCancel = onCancel
        tv.onReminder = onReminder; tv.onCommand = onCommand
        tv.insertionPointColor = accent
        tv.slashEnabled = slash; tv.remindersEnabled = reminders
        if tv.calcEnabled != smartCalc { tv.calcEnabled = smartCalc }
        if tv.accent != accent { tv.accent = accent }
        if tv.fontFamily != family { tv.fontFamily = family }
        if tv.fontSize != size { tv.fontSize = size }
        if tv.textTone != tone { tv.textTone = tone }
        if tv.string != text && !context.coordinator.editing {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
            tv.restyle()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var view: StickTextView?
        var editing = false
        init(_ parent: NoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = view else { return }
            editing = true
            tv.restyle()
            parent.onChange(tv.string)
            editing = false
        }
    }
}

import AppKit
import SwiftUI
import mSTICKCore

/// Essais sans fenêtre : rendu hors écran de l'interface dans un PNG (`mSTICK --capture-note sortie.png`…).
@MainActor
enum Capture {
    static func seedIfEmpty(_ store: NoteStore) {
        guard store.notes.isEmpty else { return }
        let samples: [(String, String, String, String)] = [
            ("Courses", "🛒", "yellow", "# Marché\n- [ ] pommes\n- [x] 4 bananes\n- [ ] fruits secs\n\nPenser à **appeler** Léa ~~lundi~~ mardi.\nhttps://holdmynotes.app\n\n| Fruit | Qté |\n| --- | --- |\n| Pomme | 3 |"),
            ("Bureau", "💼", "blue", "1. Relire le devis\n2. Envoyer la *facture*\n3. <u>Sauvegarder</u> `projet`"),
            ("Idées", "💡", "green", "Une app qui **vit** au bord de l'écran."),
            ("Perso", "", "pink", "Anniversaire de Marie le 14."),
            ("Projets", "🚀", "purple", "[lien](https://example.com)"),
        ]
        for (i, s) in samples.enumerated() {
            let n = store.create(color: s.2)
            store.update(n.id) { $0.title = s.0; $0.emoji = s.1; $0.body = s.3; $0.order = i; $0.pinned = i == 0 }
        }
        store.flush()
    }

    static func png(_ view: NSView, size: NSSize, to path: String) {
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func note(_ delegate: AppDelegate, _ path: String) {
        guard let n = delegate.store.active.first else { return }
        let vm = NoteViewModel(id: n.id, store: delegate.store)
        vm.showFormat = true
        png(NSHostingView(rootView: NoteView(vm: vm, store: delegate.store).environment(\.colorScheme, .light)), size: NSSize(width: 320, height: 380), to: path)
    }

    static func all(_ delegate: AppDelegate, _ path: String) {
        let model = AllNotesModel()
        model.selection = Set(delegate.store.active.prefix(1).map(\.id))
        png(NSHostingView(rootView: AllNotesView(store: delegate.store, model: model, open: { _ in })), size: NSSize(width: 900, height: 560), to: path)
    }

    static func settings(_ delegate: AppDelegate, _ path: String, tab: Int) {
        png(NSHostingView(rootView: SettingsView(store: delegate.store)), size: NSSize(width: 520, height: 560), to: path)
    }

    static func about(_ path: String) {
        let window = About.makeWindow()
        guard let view = window.contentView else { return }
        png(view, size: view.fittingSize, to: path)
    }
}

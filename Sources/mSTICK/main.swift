import AppKit
import mSTICKCore

let arguments = CommandLine.arguments
if arguments.contains("--selftest") { exit(MainActor.assumeIsolated { SelfTest.run() } ? 0 : 1) }

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// Pas d'icône dans le Dock : le deck et la barre des menus suffisent. Aucune fenêtre au lancement.
app.setActivationPolicy(.accessory)

/// Essais : rendu hors écran de l'interface (aucune fenêtre ouverte devant le travail en cours).
let captures: [(String, @MainActor (AppDelegate, String) -> Void)] = [
    ("--capture-note", Capture.note), ("--capture-all", Capture.all),
    ("--capture-settings", { Capture.settings($0, $1, tab: 0) }),
    ("--capture-deck", { d, p in d.deck.capture(to: p) }),
    ("--capture-about", { _, p in Capture.about(p) }),
]
if arguments.contains("--demo") { MainActor.assumeIsolated { Capture.seedIfEmpty(delegate.store) } }
for (flag, render) in captures {
    if let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) {
        let path = arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            MainActor.assumeIsolated { render(delegate, path); exit(0) }
        }
    }
}

app.run()

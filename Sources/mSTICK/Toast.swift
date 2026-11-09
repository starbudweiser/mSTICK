import AppKit
import SwiftUI

/// Petit message en bas de l'écran avec un bouton (« Annuler » après une suppression). Sans prendre le focus.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var timer: Timer?

    static func show(_ message: String, action: String, duration: TimeInterval = 10, perform: @escaping () -> Void) {
        dismiss()
        let view = ToastView(message: message, action: action) { perform(); dismiss() }
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - p.frame.width / 2, y: screen.visibleFrame.minY + 40))
        }
        p.orderFrontRegardless()
        panel = p
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in MainActor.assumeIsolated { dismiss() } }
    }

    static func dismiss() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
    }
}

private struct ToastView: View {
    let message: String, action: String, perform: () -> Void
    var body: some View {
        HStack(spacing: Socle.M.space3) {
            Text(message).socle(Socle.T.body).foregroundStyle(Socle.C.text)
            Button(action, action: perform).buttonStyle(SocleButtonStyle(.action, height: Socle.M.sizeControl)).fixedSize()
        }
        .padding(.horizontal, Socle.M.space4).padding(.vertical, Socle.M.space3)
        .background(Socle.C.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border))
        .clipShape(RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .environment(\.colorScheme, .dark)
        .padding(8)
    }
}

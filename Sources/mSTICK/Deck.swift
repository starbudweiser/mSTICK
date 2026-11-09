import AppKit
import Combine
import SwiftUI
import mSTICKCore

/// État d'un deck (un par écran) : sert à SwiftUI pour l'affichage et au contrôleur pour la taille de la fenêtre.
@MainActor
final class DeckModel: ObservableObject {
    @Published var fanned = false
    @Published var notes: [Note] = []
    @Published var overflow = 0
    let maxVisible = 8
}

private enum DeckMetrics {
    static let tab: CGFloat = 34, tabLength: CGFloat = 100, gap: CGFloat = 6, plus: CGFloat = 30
    static let stripe: CGFloat = 10, stripeLength: CGFloat = 22, stripeGap: CGFloat = 4
    static let restThickness: CGFloat = 14, fanThickness: CGFloat = 48
}

final class DeckPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DeckHostView: NSHostingView<DeckView> {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseDown(with event: NSEvent) { onClick?(); super.mouseDown(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Le deck sur le bord de l'écran : repos (fines languettes), survol (notes en éventail), ouverture (fenêtre de la note).
@MainActor
final class DeckController: NSObject {
    let store: NoteStore
    var onOpen: (UUID, NSRect) -> Void = { _, _ in }
    var onNew: () -> Void = {}
    var onShowAll: () -> Void = {}

    private struct Entry { let screen: NSScreen; let panel: DeckPanel; let model: DeckModel; let host: DeckHostView; var cancel: [AnyCancellable]; var work: DispatchWorkItem? }
    private var entries: [Entry] = []
    private let prefs = Prefs.shared
    private var clickMonitor: Any?
    private var hidden = false

    init(store: NoteStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(forName: .prefsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    var anchor: (frame: NSRect, edge: DeckEdge)? {
        guard let e = entries.first else { return nil }
        return (e.panel.frame, prefs.edge)
    }

    // MARK: Fenêtres

    func rebuild() {
        for e in entries { e.panel.orderOut(nil) }
        entries = []
        let screens = prefs.screens == .all ? NSScreen.screens : [NSScreen.screens.first].compactMap { $0 }
        for screen in screens { entries.append(makeEntry(screen)) }
        refresh()
        if !hidden { entries.forEach { $0.panel.orderFrontRegardless() } }
    }

    private func makeEntry(_ screen: NSScreen) -> Entry {
        let model = DeckModel()
        let panel = DeckPanel(contentRect: NSRect(x: 0, y: 0, width: 20, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let host = DeckHostView(rootView: DeckView(model: model, prefs: prefs, actions: actions()))
        panel.contentView = host
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        var entry = Entry(screen: screen, panel: panel, model: model, host: host, cancel: [], work: nil)
        host.onEnter = { [weak self, weak model] in
            guard let self, let model, !self.prefs.fanOnClick else { return }
            self.schedule(model, fan: true, after: self.prefs.activationDelay)
        }
        host.onExit = { [weak self, weak model] in
            guard let self, let model else { return }
            self.schedule(model, fan: false, after: 0.3)
        }
        host.onClick = { [weak self, weak model] in
            guard let self, let model, self.prefs.fanOnClick, !model.fanned else { return }
            self.schedule(model, fan: true, after: 0)
        }
        entry.cancel.append(model.$fanned.removeDuplicates().sink { [weak self, weak model] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { if let model { self?.resize(model) } } }
        })
        return entry
    }

    private func schedule(_ model: DeckModel, fan: Bool, after delay: TimeInterval) {
        guard let i = entries.firstIndex(where: { $0.model === model }) else { return }
        entries[i].work?.cancel()
        let item = DispatchWorkItem { [weak self, weak model] in
            MainActor.assumeIsolated {
                guard let self, let model else { return }
                let target = fan || self.prefs.keepOpen
                if model.fanned != target { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { model.fanned = target } }
                self.updateClickMonitor()
            }
        }
        entries[i].work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func actions() -> DeckActions {
        DeckActions(
            open: { [weak self] id, frame in self?.onOpen(id, frame) },
            new: { [weak self] in self?.onNew() },
            all: { [weak self] in self?.onShowAll() },
            pin: { [weak self] id in self?.store.update(id) { $0.pinned.toggle() } },
            archive: { [weak self] id in self?.store.setArchived([id], true) },
            delete: { [weak self] id in
                guard let self else { return }
                let gone = self.store.delete([id])
                Toast.show(L("toast.deleted"), action: L("toast.undo")) { self.store.restore(gone) }
            },
            dropEdge: { [weak self] point in self?.snapEdge(to: point) })
    }

    /// Poignée glissée : le deck va au bord le plus proche du point lâché.
    private func snapEdge(to point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let f = screen.frame
        let distances: [(DeckEdge, CGFloat)] = [(.right, f.maxX - point.x), (.left, point.x - f.minX), (.bottom, point.y - f.minY)]
        if let best = distances.min(by: { $0.1 < $1.1 }) { prefs.edge = best.0 }
    }

    // MARK: Taille et position

    func refresh() {
        let list = store.active
        for e in entries {
            e.model.notes = Array(list.prefix(e.model.maxVisible))
            e.model.overflow = max(0, list.count - e.model.maxVisible)
            if prefs.keepOpen { e.model.fanned = true } else if !prefs.keepOpen, e.model.fanned, !e.host.isMouseInside { e.model.fanned = false }
            e.panel.collectionBehavior = prefs.showOverFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary] : [.canJoinAllSpaces, .stationary]
            resize(e.model, animated: false)
        }
        updateClickMonitor()
    }

    private func resize(_ model: DeckModel, animated: Bool = true) {
        guard let e = entries.first(where: { $0.model === model }) else { return }
        let frame = targetFrame(e.screen, fanned: model.fanned, count: model.notes.count + (model.overflow > 0 ? 1 : 0))
        if animated { NSAnimationContext.runAnimationGroup { $0.duration = 0.12; e.panel.animator().setFrame(frame, display: true) } }
        else { e.panel.setFrame(frame, display: true) }
    }

    private func targetFrame(_ screen: NSScreen, fanned: Bool, count: Int) -> NSRect {
        typealias M = DeckMetrics
        let vf = screen.visibleFrame, sf = screen.frame
        let thick = fanned ? M.fanThickness : M.restThickness
        let fanLen = CGFloat(count) * (M.tabLength + M.gap) + M.plus * 2 + M.gap * 2 + 16
        let restLen = max(44, CGFloat(count) * (M.stripeLength + M.stripeGap) + 18)
        let maxLen = (prefs.edge == .bottom ? vf.width : vf.height) - 40
        let len = min(fanned ? fanLen : restLen, maxLen)
        switch prefs.edge {
        case .right: return NSRect(x: sf.maxX - thick, y: vf.midY - len / 2, width: thick, height: len)
        case .left: return NSRect(x: sf.minX, y: vf.midY - len / 2, width: thick, height: len)
        case .bottom: return NSRect(x: vf.midX - len / 2, y: vf.minY, width: len, height: thick)
        }
    }

    // MARK: Divers

    func setHidden(_ value: Bool) {
        hidden = value
        for e in entries { value ? e.panel.orderOut(nil) : e.panel.orderFrontRegardless() }
    }
    func toggleHidden() { setHidden(!hidden) }

    /// En mode « éventail au clic », un clic ailleurs referme le deck.
    private func updateClickMonitor() {
        let need = prefs.fanOnClick && !prefs.keepOpen && entries.contains { $0.model.fanned }
        if need, clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for e in self.entries where e.model.fanned && !e.panel.frame.contains(NSEvent.mouseLocation) { self.schedule(e.model, fan: false, after: 0) }
                }
            }
        } else if !need, let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    /// Ouvre le deck et rend le cadre de la languette d'une note (essais sans souris).
    func fanForTesting() { for e in entries { e.model.fanned = true } }

    func capture(to path: String) {
        guard let e = entries.first else { return }
        e.model.fanned = true
        resize(e.model, animated: false)
        let size = e.panel.frame.size
        e.host.frame = NSRect(origin: .zero, size: size)
        e.host.layoutSubtreeIfNeeded()
        guard let rep = e.host.bitmapImageRepForCachingDisplay(in: e.host.bounds) else { return }
        e.host.cacheDisplay(in: e.host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

private extension NSView {
    var isMouseInside: Bool {
        guard let window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }
}

struct DeckActions {
    var open: (UUID, NSRect) -> Void
    var new: () -> Void
    var all: () -> Void
    var pin: (UUID) -> Void
    var archive: (UUID) -> Void
    var delete: (UUID) -> Void
    var dropEdge: (NSPoint) -> Void
}

struct DeckView: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var prefs: Prefs
    let actions: DeckActions

    private typealias M = DeckMetrics
    private var vertical: Bool { prefs.edge != .bottom }
    private var alignment: Alignment { switch prefs.edge { case .right: return .trailing; case .left: return .leading; case .bottom: return .bottom } }
    private var hiddenOffset: CGSize {
        switch prefs.edge { case .right: return CGSize(width: 44, height: 0); case .left: return CGSize(width: -44, height: 0); case .bottom: return CGSize(width: 0, height: 44) }
    }
    private var layout: AnyLayout { vertical ? AnyLayout(VStackLayout(spacing: M.gap)) : AnyLayout(HStackLayout(spacing: M.gap)) }
    private var restLayout: AnyLayout { vertical ? AnyLayout(VStackLayout(spacing: M.stripeGap)) : AnyLayout(HStackLayout(spacing: M.stripeGap)) }

    var body: some View {
        ZStack(alignment: alignment) {
            rest.opacity(model.fanned ? 0 : 1).animation(.easeOut(duration: 0.12), value: model.fanned)
            fan
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .contentShape(Rectangle())
    }

    // Repos : une languette (ou un point) par note.
    private var rest: some View {
        restLayout {
            if model.notes.isEmpty { Capsule().fill(Color.gray.opacity(0.5)).frame(width: vertical ? M.stripe : M.stripeLength, height: vertical ? M.stripeLength : M.stripe) }
            switch prefs.dockStyle {
            case .stripes:
                ForEach(model.notes) { n in
                    RoundedRectangle(cornerRadius: 3).fill(Color(noteColor: n.color))
                        .frame(width: vertical ? M.stripe : M.stripeLength, height: vertical ? M.stripeLength : M.stripe)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.3), lineWidth: 0.5))
                }
            case .dots:
                ForEach(model.notes) { n in Circle().fill(Color(noteColor: n.color)).frame(width: 8, height: 8).overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 0.5)) }
            case .pile:
                ZStack {
                    ForEach(Array(model.notes.prefix(3).enumerated().reversed()), id: \.element.id) { i, n in
                        RoundedRectangle(cornerRadius: 3).fill(Color(noteColor: n.color))
                            .frame(width: vertical ? 10 : 22, height: vertical ? 22 : 10)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.3), lineWidth: 0.5))
                            .offset(x: vertical ? CGFloat(i) * -1.5 : CGFloat(i) * 4, y: vertical ? CGFloat(i) * 4 : CGFloat(i) * -1.5)
                    }
                }
                .frame(width: vertical ? 14 : 30, height: vertical ? 30 : 14)
            }
        }
        .padding(vertical ? .vertical : .horizontal, 8)
        .padding(prefs.edge == .right ? .trailing : prefs.edge == .left ? .leading : .bottom, 2)
        .allowsHitTesting(false)
    }

    // Survol : les notes sortent en cascade (45 ms entre deux).
    private var fan: some View {
        layout {
            handle.fanItem(0, model.fanned, hiddenOffset)
            ForEach(Array(model.notes.enumerated()), id: \.element.id) { i, n in
                tab(n).fanItem(i + 1, model.fanned, hiddenOffset)
            }
            if model.overflow > 0 {
                Button(action: actions.all) {
                    Text(L("deck.more", model.overflow)).socle(Socle.T.labelStrong).foregroundStyle(Color.white)
                        .frame(width: vertical ? M.tab : M.tabLength / 2, height: vertical ? M.tabLength / 2 : M.tab)
                        .background(Color(white: 0.25)).clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).fanItem(model.notes.count + 1, model.fanned, hiddenOffset)
            }
            Button(action: actions.new) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: M.plus, height: M.plus).background(Color(white: 0.22)).clipShape(Circle())
            }
            .buttonStyle(.plain).help(L("deck.new")).fanItem(model.notes.count + 2, model.fanned, hiddenOffset)
        }
        .padding(8)
    }

    private var handle: some View {
        Image(systemName: vertical ? "line.3.horizontal" : "line.3.horizontal")
            .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white.opacity(0.8))
            .frame(width: M.plus, height: 16).background(Color(white: 0.22)).clipShape(Capsule())
            .help(L("deck.drag"))
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global).onEnded { _ in actions.dropEdge(NSEvent.mouseLocation) })
    }

    private func tab(_ n: Note) -> some View {
        let hex = NoteColor.hex(n.color)
        let tone = NoteColor.isLight(hex) ? Color(white: 0.12) : Color.white
        let title = ([n.emoji, n.displayTitle(fallback: L("note.untitled"))].filter { !$0.isEmpty }).joined(separator: " ")
        return GeometryReader { proxy in
            Button { actions.open(n.id, tabFrame(proxy)) } label: {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(tone).frame(width: M.tabLength - 12)
                    .rotationEffect(.degrees(prefs.edge == .right ? -90 : prefs.edge == .left ? 90 : 0))
                    .frame(width: vertical ? M.tab : M.tabLength, height: vertical ? M.tabLength : M.tab)
                    .background(Color(noteColor: n.color))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.25), lineWidth: 1))
                    .overlay(alignment: .topTrailing) { if n.pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(tone.opacity(0.7)).padding(3) } }
            }
            .buttonStyle(.plain)
        }
        .frame(width: vertical ? M.tab : M.tabLength, height: vertical ? M.tabLength : M.tab)
        .help(title)
        .contextMenu {
            Button(L("tab.pin_" + (n.pinned ? "off" : "on"))) { actions.pin(n.id) }
            Button(L("tab.archive")) { actions.archive(n.id) }
            Button(L("tab.delete"), role: .destructive) { actions.delete(n.id) }
        }
    }

    /// Cadre (en coordonnées d'écran) de la languette, pour poser la note à côté.
    private func tabFrame(_ proxy: GeometryProxy) -> NSRect {
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2)
    }
}

private extension View {
    func fanItem(_ index: Int, _ fanned: Bool, _ hidden: CGSize) -> some View {
        self.offset(fanned ? .zero : hidden)
            .opacity(fanned ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.78).delay(fanned ? Double(index) * 0.045 : 0), value: fanned)
    }
}

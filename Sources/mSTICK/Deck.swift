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

/// Mesures du deck, dessiné comme sur le bord droit puis tourné pour les autres bords.
enum DeckMetrics {
    static let cardLength: CGFloat = 96, overlap: CGFloat = 12, baseWidth: CGFloat = 46, stair: CGFloat = 3, hidden: CGFloat = 24
    static let restThickness: CGFloat = 16, fanThickness: CGFloat = 84
    static let dash: CGFloat = 16, dashGap: CGFloat = 6
    static let gripHeight: CGFloat = 16, plus: CGFloat = 26

    static func fanLength(count: Int) -> CGFloat { CGFloat(count) * (cardLength - overlap) + overlap + gripHeight + plus + 36 }
    static func restLength(count: Int) -> CGFloat { max(40, CGFloat(max(count, 1)) * (dash + dashGap) + 16) }
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

// MARK: - Déplacement du deck : la cible (écran + bord) s'affiche en direct

/// Écran le plus proche d'un point (bords compris) et bord de cet écran le plus proche.
@MainActor
enum DeckTarget {
    static func resolve(_ point: NSPoint) -> (screen: NSScreen, edge: DeckEdge)? {
        func distance(_ r: NSRect) -> CGFloat {
            let dx = max(r.minX - point.x, 0, point.x - r.maxX), dy = max(r.minY - point.y, 0, point.y - r.maxY)
            return hypot(dx, dy)
        }
        // L'écran qui contient le point (la frontière appartient à l'écran de droite), sinon le plus proche.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.screens.min(by: { distance($0.frame) < distance($1.frame) }) else { return nil }
        let f = screen.frame
        let edges: [(DeckEdge, CGFloat)] = [(.right, abs(f.maxX - point.x)), (.left, abs(point.x - f.minX)), (.bottom, abs(point.y - f.minY)), (.top, abs(f.maxY - point.y))]
        return (screen, edges.min(by: { $0.1 < $1.1 })!.0)
    }
}

@MainActor
final class ZonesModel: ObservableObject {
    @Published var target: DeckEdge?
}

private struct ZonesView: View {
    @ObservedObject var model: ZonesModel
    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.black.opacity(model.target == nil ? 0.12 : 0)
                ForEach(DeckEdge.allCases, id: \.self) { edge in
                    let on = model.target == edge
                    Capsule().fill(on ? Color(red: 1.0, green: 0.80, blue: 0.22) : Color.white.opacity(model.target == nil ? 0.0 : 0.35))
                        .frame(width: edge.isVertical ? (on ? 10 : 6) : g.size.width * 0.3, height: edge.isVertical ? g.size.height * 0.3 : (on ? 10 : 6))
                        .shadow(color: .black.opacity(on ? 0.4 : 0), radius: 8)
                        .position(x: edge == .left ? 10 : edge == .right ? g.size.width - 10 : g.size.width / 2,
                                  y: edge == .top ? 10 : edge == .bottom ? g.size.height - 10 : g.size.height / 2)
                }
            }
            .animation(.easeOut(duration: 0.12), value: model.target)
        }
    }
}

/// Un voile par écran pendant le glissement de la poignée : l'écran visé et son bord s'allument.
@MainActor
final class DropZones {
    private var items: [(screen: NSScreen, panel: NSPanel, model: ZonesModel)] = []

    func show() {
        hide()
        for screen in NSScreen.screens {
            let model = ZonesModel()
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: ZonesView(model: model))
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            items.append((screen, panel, model))
        }
    }

    func update(_ point: NSPoint) {
        let target = DeckTarget.resolve(point)
        for item in items { item.model.target = (target?.screen === item.screen) ? target?.edge : nil }
    }

    func hide() { items.forEach { $0.panel.orderOut(nil) }; items = [] }
}

// MARK: - Contrôleur

/// Le deck sur le bord de l'écran : repos (capsule), survol (cartes en écailles), ouverture (la note glisse hors du deck).
@MainActor
final class DeckController: NSObject {
    let store: NoteStore
    var onOpen: (UUID, NSRect) -> Void = { _, _ in }
    var onNew: () -> Void = {}
    var onShowAll: () -> Void = {}

    private struct Entry { let screen: NSScreen; let panel: DeckPanel; let model: DeckModel; let host: DeckHostView; var cancel: [AnyCancellable]; var work: DispatchWorkItem? }
    private var entries: [Entry] = []
    private let prefs = Prefs.shared
    private let zones = DropZones()
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
        let screens: [NSScreen]
        switch prefs.screenChoice {
        case "all": screens = NSScreen.screens
        case "main": screens = [NSScreen.primary].compactMap { $0 }
        default: screens = [NSScreen.screens.first { String($0.displayID) == prefs.screenChoice } ?? NSScreen.primary].compactMap { $0 }
        }
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
            guard let self, let model, NSEvent.pressedMouseButtons == 0 else { return } // pas pendant un glissement de la poignée
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
            dragMove: { [weak self] point in
                guard let self else { return }
                if self.zones.isEmpty { self.zones.show() }
                self.zones.update(point)
            },
            dropEdge: { [weak self] point in self?.zones.hide(); self?.snap(to: point) })
    }

    /// Poignée lâchée : le deck va sur l'écran visé, au bord visé.
    private func snap(to point: NSPoint) {
        guard let target = DeckTarget.resolve(point) else { return }
        if prefs.screenChoice != "all" { prefs.screenChoice = target.screen == NSScreen.primary ? "main" : String(target.screen.displayID) }
        prefs.edge = target.edge
    }

    // MARK: Taille et position

    func refresh() {
        let list = store.active
        for e in entries {
            e.model.notes = Array(list.prefix(e.model.maxVisible))
            e.model.overflow = max(0, list.count - e.model.maxVisible)
            if prefs.keepOpen { e.model.fanned = true } else if e.model.fanned, !e.host.isMouseInside { e.model.fanned = false }
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
        let maxLen = (prefs.edge.isVertical ? vf.height : vf.width) - 40
        let len = min(fanned ? M.fanLength(count: count) : M.restLength(count: count), maxLen)
        switch prefs.edge {
        case .right: return NSRect(x: sf.maxX - thick, y: vf.midY - len / 2, width: thick, height: len)
        case .left: return NSRect(x: sf.minX, y: vf.midY - len / 2, width: thick, height: len)
        case .bottom: return NSRect(x: vf.midX - len / 2, y: vf.minY, width: len, height: thick)
        case .top: return NSRect(x: vf.midX - len / 2, y: vf.maxY - thick, width: len, height: thick)
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

    /// Essai : affiche les zones de dépôt comme pendant un glissement, le pointeur étant en `point`.
    func showZonesForTesting(_ point: NSPoint) { zones.show(); zones.update(point) }

    func fanForTesting() { for e in entries { e.model.fanned = true } }

    func capture(to path: String, fanned: Bool = true) {
        guard let e = entries.first else { return }
        e.model.fanned = fanned
        resize(e.model, animated: false)
        let size = e.panel.frame.size
        e.host.frame = NSRect(origin: .zero, size: size)
        e.host.layoutSubtreeIfNeeded()
        guard let rep = e.host.bitmapImageRepForCachingDisplay(in: e.host.bounds) else { return }
        e.host.cacheDisplay(in: e.host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

private extension DropZones { var isEmpty: Bool { items.isEmpty } }

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
    var dragMove: (NSPoint) -> Void
    var dropEdge: (NSPoint) -> Void
}

// MARK: - Dessin

/// Le deck est dessiné une seule fois comme sur le bord droit (cartes qui dépassent vers la gauche), puis tourné
/// selon le bord choisi : l'écran, le bord et le sens des étiquettes restent cohérents partout.
struct DeckView: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var prefs: Prefs
    let actions: DeckActions

    private var angle: Double {
        switch prefs.edge { case .right: return 0; case .left: return 180; case .bottom: return 90; case .top: return -90 }
    }

    var body: some View {
        GeometryReader { g in
            let vertical = prefs.edge.isVertical
            let canvas = CGSize(width: vertical ? g.size.width : g.size.height, height: vertical ? g.size.height : g.size.width)
            DeckCanvas(model: model, prefs: prefs, actions: actions, labelFlip: prefs.edge == .top)
                .frame(width: canvas.width, height: canvas.height)
                .rotationEffect(.degrees(angle))
                .frame(width: g.size.width, height: g.size.height)
        }
        .contentShape(Rectangle())
    }
}

private struct DeckCanvas: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var prefs: Prefs
    let actions: DeckActions
    let labelFlip: Bool
    @State private var shown = false
    private typealias M = DeckMetrics
    /// Le premier de la liste reste en haut (colonne) ou à gauche (rangée), quel que soit le bord.
    private var ordered: [Note] { prefs.edge == .bottom || prefs.edge == .left ? model.notes.reversed() : model.notes }

    var body: some View {
        Group {
            if model.fanned { fan.onAppear { shown = true }.onDisappear { shown = false } } else { rest }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    // Repos : une capsule sombre translucide, une pastille de couleur par note.
    private var rest: some View {
        VStack(spacing: M.dashGap) {
            if model.notes.isEmpty { Capsule().fill(Color.white.opacity(0.35)).frame(width: 6, height: M.dash) }
            switch prefs.dockStyle {
            case .stripes:
                ForEach(ordered) { n in Capsule().fill(Color(noteColor: n.color)).frame(width: 6, height: M.dash) }
            case .dots:
                ForEach(ordered) { n in Circle().fill(Color(noteColor: n.color)).frame(width: 7, height: 7) }
            case .pile:
                ZStack {
                    ForEach(Array(model.notes.prefix(3).enumerated().reversed()), id: \.element.id) { i, n in
                        Capsule().fill(Color(noteColor: n.color)).frame(width: 6, height: M.dash).offset(x: CGFloat(i) * -1.5, y: CGFloat(i) * 4)
                    }
                }.frame(height: M.dash + 8)
            }
        }
        .padding(.vertical, 8).frame(width: 12)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        .padding(.trailing, 3)
        .allowsHitTesting(false)
    }

    // Survol : les cartes se posent en écailles, 45 ms entre deux, chacune avec son étiquette verticale.
    private var fan: some View {
        VStack(alignment: .trailing, spacing: -M.overlap) {
            handle.fanItem(0, shown).padding(.trailing, 22).padding(.bottom, M.overlap + 4)
            ForEach(Array(ordered.enumerated()), id: \.element.id) { i, n in
                card(n, index: i).fanItem(i + 1, shown).zIndex(Double(i))
            }
            if model.overflow > 0 {
                Button(action: actions.all) {
                    Text(L("deck.more", model.overflow)).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white)
                        .frame(width: 34, height: 22).background(Capsule().fill(Color.black.opacity(0.55)))
                }.buttonStyle(.plain).padding(.trailing, 22).padding(.top, M.overlap + 6).fanItem(model.notes.count + 1, shown)
            }
            Button(action: actions.new) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.25))
                    .frame(width: M.plus, height: M.plus).background(Circle().fill(Color(white: 0.9)))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
            .buttonStyle(.plain).help(L("deck.new")).padding(.trailing, 22).padding(.top, M.overlap + 10)
            .fanItem(model.notes.count + 2, shown)
        }
        .padding(.vertical, 10)
    }

    private var handle: some View {
        HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.8)).frame(width: 3.5, height: 3.5) } }
            .rotationEffect(.degrees(90))
            .frame(width: 14, height: 24)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .help(L("deck.drag"))
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in actions.dragMove(NSEvent.mouseLocation) }
                .onEnded { _ in actions.dropEdge(NSEvent.mouseLocation) })
    }

    private func card(_ n: Note, index: Int) -> some View {
        let hex = NoteColor.hex(n.color)
        let tone = NoteColor.isLight(hex) ? Color(white: 0.2) : Color.white
        let label = String(n.displayTitle(fallback: L("note.untitled")).uppercased().prefix(8))
        let visible = M.baseWidth + CGFloat(min(index, 7)) * M.stair
        let title = ([n.emoji, n.displayTitle(fallback: L("note.untitled"))].filter { !$0.isEmpty }).joined(separator: " ")
        return GeometryReader { proxy in
            Button { actions.open(n.id, tabFrame(proxy)) } label: {
                HStack(spacing: 0) {
                    Text(label).font(.system(size: 10, weight: .bold)).tracking(1.4).lineLimit(1).fixedSize()
                        .foregroundStyle(tone.opacity(0.7))
                        .rotationEffect(.degrees(labelFlip ? 90 : -90))
                        .frame(width: 30, height: M.cardLength)
                        .overlay(alignment: .topLeading) { if n.pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(tone.opacity(0.6)).padding(5) } }
                    Rectangle().fill(Color.clear).frame(width: 1, height: M.cardLength - 20)
                        .overlay(DashedLine().stroke(tone.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    Spacer(minLength: 0)
                }
                .frame(width: visible + M.hidden, height: M.cardLength, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(noteColor: n.color)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 5, x: -1, y: 2)
                .rotationEffect(.degrees(-1), anchor: .trailing)
                .offset(x: 0)
            }
            .buttonStyle(.plain)
        }
        .frame(width: visible + M.hidden, height: M.cardLength)
        .padding(.trailing, -M.hidden)
        .help(title)
        .contextMenu {
            Button(L("tab.pin_" + (n.pinned ? "off" : "on"))) { actions.pin(n.id) }
            Button(L("tab.archive")) { actions.archive(n.id) }
            Button(L("tab.delete"), role: .destructive) { actions.delete(n.id) }
        }
    }

    /// Point de l'écran où s'est fait le clic : la note s'ouvre à côté.
    private func tabFrame(_ proxy: GeometryProxy) -> NSRect {
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2)
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) } }
}

private extension View {
    /// Les cartes arrivent du bord, l'une après l'autre.
    func fanItem(_ index: Int, _ fanned: Bool) -> some View {
        self.offset(x: fanned ? 0 : 90)
            .opacity(fanned ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.78).delay(fanned ? Double(index) * 0.045 : 0), value: fanned)
    }
}

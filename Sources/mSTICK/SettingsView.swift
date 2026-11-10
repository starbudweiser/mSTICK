import AppKit
import ServiceManagement
import SwiftUI
import mSTICKCore

private enum SettingsTab: String, CaseIterable { case general, keyboard, data, updates }

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var store: NoteStore
    @State private var tab: SettingsTab = .general
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var newColor = Color(red: 1, green: 0.85, blue: 0.4)

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases, id: \.self) { Text(L("settings.tab." + $0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(Socle.M.space3)
            Divider().overlay(Socle.C.border)
            ScrollView {
                VStack(alignment: .leading, spacing: Socle.M.space4) {
                    switch tab {
                    case .general: general
                    case .keyboard: keyboard
                    case .data: data
                    case .updates: updates
                    }
                }
                .padding(Socle.M.space4).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Socle.C.bg)
        .frame(width: 520, height: 560)
    }

    // MARK: Général

    private var general: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            section("settings.look") {
                row("settings.appearance") { Picker("", selection: $prefs.appearance) { ForEach(NoteAppearance.allCases, id: \.self) { Text(L("appearance." + $0.rawValue)).tag($0) } }.labelsHidden().frame(width: 180) }
                row("settings.defaultfont") {
                    Picker("", selection: $prefs.defaultFont) {
                        Text(L("note.font.system")).tag("")
                        ForEach(["Avenir Next", "Georgia", "Menlo", "Bradley Hand", "Noteworthy", "Marker Felt", "Chalkboard SE"].filter { NSFontManager.shared.availableFontFamilies.contains($0) }, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 180)
                }
                row("settings.fontsize") { Picker("", selection: $prefs.fontSize) { ForEach(Prefs.fontSizes, id: \.self) { Text("\($0) pt").tag($0) } }.labelsHidden().frame(width: 180) }
                VStack(alignment: .leading, spacing: Socle.M.space2) {
                    Text(L("settings.colors")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                    HStack(spacing: 6) {
                        ForEach(prefs.customColors, id: \.self) { hex in
                            Circle().fill(Color(noteColor: hex)).frame(width: 22, height: 22).overlay(Circle().stroke(Socle.C.borderStrong))
                                .help(L("settings.colors.remove"))
                                .onTapGesture { prefs.customColors.removeAll { $0 == hex } }
                        }
                        ColorPicker("", selection: $newColor, supportsOpacity: false).labelsHidden()
                        Button(L("settings.colors.add")) { if let hex = hexString(newColor), !prefs.customColors.contains(hex) { prefs.customColors.append(hex) } }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    }
                }
            }
            section("settings.close") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(CloseStyle.allCases, id: \.self) { style in
                        Button { prefs.closeStyle = style } label: {
                            VStack(spacing: 6) {
                                CloseGlyph(style: style, color: Socle.C.text, size: 14).frame(height: 18)
                                Text(L("close." + style.rawValue)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(prefs.closeStyle == style ? Socle.C.accent.opacity(0.18) : Socle.C.surfaceRaised)
                            .overlay(Rectangle().stroke(prefs.closeStyle == style ? Socle.C.accent : Socle.C.border))
                        }.buttonStyle(.plain)
                    }
                }
                row("settings.closepos") {
                    Picker("", selection: $prefs.closeLeft) { Text(L("settings.closepos.left")).tag(true); Text(L("settings.closepos.right")).tag(false) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
            }
            section("settings.smart") {
                toggle("settings.autostack", $prefs.autoStack)
                toggle("settings.smartcalc", $prefs.smartCalc)
                toggle("settings.slash", $prefs.slashCommands)
                toggle("settings.reminders", $prefs.reminders)
                toggle("settings.fullscreen", $prefs.showOverFullScreen)
            }
            section("settings.system") {
                toggle("settings.menubar", $prefs.menuBarIcon)
                Toggle(L("settings.login"), isOn: Binding(get: { startAtLogin }, set: setLogin)).toggleStyle(.checkbox).socle(Socle.T.body)
            }
        }
    }

    private func hexString(_ color: Color) -> String? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    private func setLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Clavier

    private var keyboard: some View {
        section("settings.shortcuts") {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                row("hotkey." + action.rawValue) { HotkeyRecorder(action: action) }
            }
            Text(L("settings.shortcuts.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
        }
    }

    // MARK: Données

    private var data: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            section("settings.sync") {
                toggle("settings.sync.enable", $prefs.syncEnabled)
                folderRow(path: $prefs.syncPath, enabled: prefs.syncEnabled)
                Text(L("settings.sync.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                HStack {
                    Button(L("settings.sync.now")) { store.syncNow() }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize().disabled(!prefs.syncEnabled)
                    if let error = store.lastSyncError { Text(error).socle(Socle.T.meta).foregroundStyle(Socle.C.danger).lineLimit(2) }
                }
            }
            section("settings.markdown") {
                toggle("settings.markdown.enable", $prefs.markdownEnabled)
                folderRow(path: $prefs.markdownPath, enabled: prefs.markdownEnabled)
                Text(L("settings.markdown.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
            }
            section("settings.privacy") {
                Text(L("settings.privacy.text")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func folderRow(path: Binding<String>, enabled: Bool) -> some View {
        HStack {
            Text(path.wrappedValue.isEmpty ? L("settings.folder.none") : (path.wrappedValue as NSString).abbreviatingWithTildeInPath)
                .socle(Socle.T.monoSm).foregroundStyle(Socle.C.textMuted).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(L("settings.folder.choose")) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
            }
            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize().disabled(!enabled)
        }
    }

    // MARK: Mises à jour

    private var updates: some View {
        section("settings.updates") {
            toggle("settings.autoupdate", $prefs.autoUpdate)
            Button(L("update.check")) { UpdateEngine.shared.checkNow() }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            Text(L("about.version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))
                .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
        }
    }

    // MARK: Briques

    private func section<C: View>(_ key: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            Text(L(key)).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            VStack(alignment: .leading, spacing: Socle.M.space3) { content() }
                .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
                .background(Socle.C.surface).overlay(Rectangle().stroke(Socle.C.border))
        }
    }

    private func row<C: View>(_ key: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(L(key)).socle(Socle.T.body).foregroundStyle(Socle.C.text); Spacer(); control() }
    }

    private func toggle(_ key: String, _ binding: Binding<Bool>) -> some View {
        Toggle(L(key), isOn: binding).toggleStyle(.checkbox).socle(Socle.T.body)
    }
}

/// Saisie d'un raccourci global : Échap annule, ⌫ efface.
struct HotkeyRecorder: View {
    let action: HotkeyAction
    @ObservedObject var prefs = Prefs.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: Socle.M.space2) {
                Button(recording ? L("shortcut.recording") : prefs.hotkey(action).map(KeyName.label) ?? L("shortcut.none")) { recording ? stop() : start() }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).frame(minWidth: 110)
                if prefs.hotkeys[action.rawValue] != nil, !recording {
                    Button(L("shortcut.reset")) { prefs.resetHotkey(action) }.buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            if let message { Text(message).socle(Socle.T.meta).foregroundStyle(Socle.C.danger) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil; recording = true
        HotkeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in handle(event); return nil }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }

    private func handle(_ event: NSEvent) {
        let code = Int(event.keyCode)
        if code == 53 { stop(); return }
        if code == 51 { stop(); prefs.setHotkey(action, nil); return }
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        guard !flags.isEmpty || KeyName.isFunctionKey(code) else { message = L("shortcut.needs.modifier"); return }
        let hotkey = Hotkey(keyCode: code, modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        if let other = HotkeyAction.allCases.first(where: { $0 != action && prefs.hotkey($0) == hotkey }) {
            message = L("shortcut.taken.other", L("hotkey." + other.rawValue)); return
        }
        stop()
        prefs.setHotkey(action, hotkey)
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    func show(store: NoteStore, quietly: Bool = false) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = L("settings.title")
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            w.center()
            window = w
        }
        if quietly { window?.orderFront(nil) } else { window?.present() }
    }
    var contentView: NSView? { window?.contentView }
}

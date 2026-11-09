import AppKit
import Carbon.HIToolbox
import mSTICKCore

/// Raccourcis globaux par l'API Carbon : aucune autorisation d'accessibilité n'est nécessaire.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    var onPress: ((HotkeyAction) -> Void)?
    private var registered: [EventHotKeyRef] = []
    private var targets: [UInt32: HotkeyAction] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x6D53544B // « mSTK »

    /// Enregistre les raccourcis ; rend les actions dont le raccourci est déjà pris ailleurs.
    @discardableResult
    func register(_ hotkeys: [(HotkeyAction, Hotkey)]) -> Set<HotkeyAction> {
        unregisterAll()
        installHandler()
        var failures = Set<HotkeyAction>()
        for (index, (action, hotkey)) in hotkeys.enumerated() {
            let number = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotkey.keyCode), Self.carbonModifiers(hotkey.modifiers),
                                             EventHotKeyID(signature: Self.signature, id: number),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered.append(ref); targets[number] = action } else { failures.insert(action) }
        }
        return failures
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []; targets = [:]
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let number = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotkeyCenter.shared.fire(number) } }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func fire(_ number: UInt32) { if let action = targets[number] { onPress?(action) } }

    private static func carbonModifiers(_ mask: UInt) -> UInt32 {
        var out = 0
        if mask & Hotkey.command != 0 { out |= cmdKey }
        if mask & Hotkey.option != 0 { out |= optionKey }
        if mask & Hotkey.control != 0 { out |= controlKey }
        if mask & Hotkey.shift != 0 { out |= shiftKey }
        return UInt32(out)
    }
}

/// Écriture d'un raccourci selon la disposition de clavier active (AZERTY compris).
enum KeyName {
    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "␣", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func isFunctionKey(_ keyCode: Int) -> Bool { special[keyCode]?.hasPrefix("F") == true }

    static func label(_ hotkey: Hotkey) -> String {
        var out = ""
        if hotkey.modifiers & Hotkey.control != 0 { out += "⌃" }
        if hotkey.modifiers & Hotkey.option != 0 { out += "⌥" }
        if hotkey.modifiers & Hotkey.shift != 0 { out += "⇧" }
        if hotkey.modifiers & Hotkey.command != 0 { out += "⌘" }
        return out + key(hotkey.keyCode)
    }

    private static func key(_ keyCode: Int) -> String {
        if let name = special[keyCode] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(keyCode)" }
        let layout = unsafeBitCast(raw, to: CFData.self) as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

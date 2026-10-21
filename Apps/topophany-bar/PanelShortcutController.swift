import AppKit
import Carbon.HIToolbox
import Observation
import TopophanyKit

/// Owns the panel's global hotkey. Exclusive registration detects other
/// registered hotkeys without installing a keyboard tap or reading typing.
@MainActor
@Observable
final class PanelShortcutController {
    enum Issue: Error, Equatable {
        case invalid, appConflict, systemConflict, systemUnavailable, inUse, registrationFailed

        var message: String {
            switch self {
            case .invalid: tr("Include Command, Control or Option with another key.")
            case .appConflict: tr("This shortcut is used by Topophany. Choose another combination.")
            case .systemConflict: tr("This shortcut is used by macOS. Choose another combination.")
            case .systemUnavailable: tr("System shortcuts could not be checked. Try recording again.")
            case .inUse: tr("This shortcut is already registered by another app. Choose another combination.")
            case .registrationFailed: tr("macOS could not register this shortcut. Try another combination.")
            }
        }
    }

    private(set) var shortcut: PanelShortcut?
    private(set) var issue: Issue?
    private(set) var isRecording = false
    @ObservationIgnored var onPress: (() -> Void)?
    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var symbolicMode: UnsafeMutableRawPointer?
    @ObservationIgnored private let systemShortcuts: @MainActor () throws -> [PanelShortcut]
    private static let signature: OSType = 0x54504252 // TPBR

    init(systemShortcuts: @escaping @MainActor () throws -> [PanelShortcut] = PanelShortcutController.readSystemShortcuts) {
        self.systemShortcuts = systemShortcuts
    }

    isolated deinit { stop() }

    /// Settings keep the user's choice even if it cannot be registered on
    /// this launch; the General tab shows the registration failure.
    func configure(_ shortcut: PanelShortcut?) {
        let changed = self.shortcut != shortcut
        self.shortcut = shortcut
        guard !isRecording else { return }
        if changed { unregister() }
        issue = nil
        guard let shortcut else { unregister(); return }
        do {
            try validate(shortcut)
            if hotKey == nil { try register(shortcut) }
        } catch {
            unregister()
            issue = (error as? Issue) ?? .registrationFailed
        }
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        issue = nil
        unregister()
        // This request applies only while this app is frontmost. macOS
        // may leave protected system shortcuts enabled without access.
        symbolicMode = PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabled))
    }

    /// A failed candidate leaves the saved shortcut intact. Its global
    /// registration resumes when the user finishes or cancels recording.
    @discardableResult
    func record(_ candidate: PanelShortcut) -> Bool {
        guard isRecording else { return false }
        do {
            try validate(candidate)
            try register(candidate)
            shortcut = candidate
            issue = nil
            finishRecording()
            return true
        } catch {
            issue = (error as? Issue) ?? .registrationFailed
            return false
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        finishRecording()
        configure(shortcut)
    }

    func stop() {
        finishRecording()
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func finishRecording() {
        isRecording = false
        if let symbolicMode { PopSymbolicHotKeyMode(symbolicMode) }
        symbolicMode = nil
    }

    private func validate(_ candidate: PanelShortcut) throws {
        guard candidate.isValid else { throw Issue.invalid }
        // The panel handles these even when no main menu is installed.
        let commandKeys: Set<UInt32> = [0, 6, 7, 8, 9, 12, 13, 31, 4, 43]
        if candidate.modifiers == .command && commandKeys.contains(candidate.keyCode)
            || candidate.modifiers == [.command, .shift] && candidate.keyCode == 6
            || candidate.modifiers == [.command, .option] && candidate.keyCode == 4 {
            throw Issue.appConflict
        }
        let reserved: [PanelShortcut]
        do { reserved = try systemShortcuts() } catch { throw Issue.systemUnavailable }
        if reserved.contains(candidate) { throw Issue.systemConflict }
    }

    private func register(_ shortcut: PanelShortcut) throws {
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == PanelShortcutController.signature, id.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                MainActor.assumeIsolated {
                    let controller = Unmanaged<PanelShortcutController>.fromOpaque(context).takeUnretainedValue()
                    if !controller.isRecording, controller.hotKey != nil { controller.onPress?() }
                }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw Issue.registrationFailed }
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr { throw Issue.inUse }
            throw Issue.registrationFailed
        }
        hotKey = reference
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    static func readSystemShortcuts() throws -> [PanelShortcut] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let array else { throw Issue.systemUnavailable }
        let entries = array.takeRetainedValue() as NSArray
        return entries.compactMap { entry in
            guard let entry = entry as? [String: Any],
                  (entry[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true,
                  let key = entry[kHISymbolicHotKeyCode] as? NSNumber,
                  let modifiers = entry[kHISymbolicHotKeyModifiers] as? NSNumber else { return nil }
            return PanelShortcut(keyCode: key.uint32Value, modifiers: .init(carbon: modifiers.uint32Value))
        }
    }
}

extension PanelShortcut.Modifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        self = []
        if eventFlags.contains(.control) { insert(.control) }
        if eventFlags.contains(.option) { insert(.option) }
        if eventFlags.contains(.shift) { insert(.shift) }
        if eventFlags.contains(.command) { insert(.command) }
    }

    init(carbon: UInt32) {
        self = []
        if carbon & UInt32(controlKey) != 0 { insert(.control) }
        if carbon & UInt32(optionKey) != 0 { insert(.option) }
        if carbon & UInt32(shiftKey) != 0 { insert(.shift) }
        if carbon & UInt32(cmdKey) != 0 { insert(.command) }
    }

    var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

extension PanelShortcut {
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    var display: String { modifiers.symbols + keyDisplay }

    private var keyDisplay: String {
        let special: [UInt32: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
                                       115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let special = special[keyCode] { return special == "Space" ? tr("Space") : special }
        let functions: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        if let i = functions.firstIndex(of: keyCode) { return "F\(i + 1)" }
        // Translate the physical key with the current layout, falling back
        // to an ASCII layout for input methods without a Unicode layout.
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        let current = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let data = TISGetInputSourceProperty(current, kTISPropertyUnicodeKeyLayoutData)
            ?? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        if let data {
            let layout = unsafeBitCast(data, to: CFData.self)
            let pointer = UnsafeRawPointer(CFDataGetBytePtr(layout)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            if UCKeyTranslate(pointer, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                              OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, characters.count, &length, &characters) == noErr,
               length > 0 {
                return String(utf16CodeUnits: characters, count: length).uppercased()
            }
        }
        return "[\(keyCode)]"
    }
}

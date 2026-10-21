import AppKit
import Carbon.HIToolbox
import Testing
import TopophanyKit

// The standalone app-shell tests build the controller directly, without
// launching the app or reading the user's settings and login item.
func tr(_ key: String.LocalizationValue) -> String { String(localized: key) }

@MainActor
@Suite(.serialized) struct PanelShortcutTests {
    private let first = PanelShortcut(keyCode: 90, modifiers: [.command, .control, .option, .shift])
    private let second = PanelShortcut(keyCode: 80, modifiers: [.command, .control, .option, .shift])

    @Test func enabledSystemShortcutsAreRejectedAndTheOldChoiceIsRestored() throws {
        let reserved = second
        let controller = PanelShortcutController(systemShortcuts: { [reserved] })
        defer { controller.stop() }
        controller.configure(first)
        #expect(controller.issue == nil)
        controller.beginRecording()
        #expect(!controller.record(second))
        #expect(controller.issue == .systemConflict)
        #expect(controller.shortcut == first)
        #expect(controller.isRecording)
        controller.cancelRecording()
        #expect(controller.issue == nil)
        #expect(controller.shortcut == first)
        try expectRegistered(first)
    }

    @Test func replacingClearingAndRecordingTheSameKeyReleaseRegistrations() throws {
        let controller = PanelShortcutController(systemShortcuts: { [] })
        defer { controller.stop() }
        controller.configure(first)
        #expect(controller.issue == nil)
        controller.beginRecording()
        #expect(controller.record(first))
        try expectRegistered(first)
        controller.beginRecording()
        #expect(controller.record(second))
        #expect(!controller.isRecording)
        #expect(controller.shortcut == second)
        try expectAvailable(first)
        try expectRegistered(second)
        controller.configure(nil)
        #expect(controller.issue == nil)
        try expectAvailable(second)
    }

    @Test func existingGlobalRegistrationCannotBeReplaced() throws {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(second.keyCode, second.carbonModifiers,
                                         EventHotKeyID(signature: 0x54455354, id: 2), GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &reference)
        #expect(result == noErr)
        let occupied = try #require(reference)
        defer { UnregisterEventHotKey(occupied) }
        let controller = PanelShortcutController(systemShortcuts: { [] })
        defer { controller.stop() }
        controller.configure(first)
        controller.beginRecording()
        #expect(!controller.record(second))
        #expect(controller.issue == .inUse)
        #expect(controller.shortcut == first)
        controller.cancelRecording()
        try expectRegistered(first)
    }

    @Test func systemLookupFailureAndInvalidKeysCannotBeSaved() {
        let controller = PanelShortcutController(systemShortcuts: { throw PanelShortcutController.Issue.systemUnavailable })
        defer { controller.stop() }
        controller.beginRecording()
        #expect(!controller.record(first))
        #expect(controller.issue == .systemUnavailable)
        #expect(!controller.record(PanelShortcut(keyCode: 0, modifiers: .shift)))
        #expect(controller.issue == .invalid)
        #expect(!controller.record(PanelShortcut(keyCode: 12, modifiers: .command)))
        #expect(controller.issue == .appConflict)
        #expect(controller.shortcut == nil)
    }

    @Test func savedShortcutIsRecheckedAndCanRecover() throws {
        let reserved = ReservedShortcuts()
        reserved.values = [first]
        let controller = PanelShortcutController(systemShortcuts: { reserved.values })
        defer { controller.stop() }
        controller.configure(first)
        #expect(controller.issue == .systemConflict)
        #expect(controller.shortcut == first)
        try expectAvailable(first)
        reserved.values = []
        controller.configure(first)
        #expect(controller.issue == nil)
        try expectRegistered(first)
    }

    @Test func readsRealSystemShortcutsAndDisplaysKeys() throws {
        _ = try PanelShortcutController.readSystemShortcuts()
        #expect(PanelShortcut(keyCode: 49, modifiers: [.control, .option]).display == "⌃⌥Space")
        #expect(first.display == "⌃⌥⇧⌘F20")
        #expect(PanelShortcut.Modifiers(carbon: first.carbonModifiers) == first.modifiers)
    }

    @Test func nativeHotKeyEventsInvokeTheActionExceptWhileRecording() throws {
        let controller = PanelShortcutController(systemShortcuts: { [] })
        defer { controller.stop() }
        let counter = PressCounter()
        controller.onPress = { counter.value += 1 }
        controller.configure(first)
        try pressEvent()
        #expect(counter.value == 1)
        controller.beginRecording()
        try pressEvent()
        #expect(counter.value == 1)
        controller.cancelRecording()
        try pressEvent()
        #expect(counter.value == 2)
        try pressEvent(signature: 0x54455354)
        #expect(counter.value == 2)
    }

    private func pressEvent(signature: OSType = 0x54504252) throws {
        var event: EventRef?
        #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr)
        let press = try #require(event)
        defer { ReleaseEvent(press) }
        var id = EventHotKeyID(signature: signature, id: 1)
        #expect(SetEventParameter(press, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  MemoryLayout<EventHotKeyID>.size, &id) == noErr)
        _ = SendEventToEventTarget(press, GetApplicationEventTarget())
    }

    private func expectRegistered(_ shortcut: PanelShortcut) throws {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
                                         EventHotKeyID(signature: 0x54455354, id: 3), GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &reference)
        if let reference { UnregisterEventHotKey(reference) }
        #expect(status == eventHotKeyExistsErr)
    }

    private func expectAvailable(_ shortcut: PanelShortcut) throws {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
                                         EventHotKeyID(signature: 0x54455354, id: 4), GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &reference)
        if let reference { UnregisterEventHotKey(reference) }
        #expect(status == noErr)
    }
}

@MainActor
private final class ReservedShortcuts {
    var values: [PanelShortcut] = []
}

@MainActor
private final class PressCounter {
    var value = 0
}

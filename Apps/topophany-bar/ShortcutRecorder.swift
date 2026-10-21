import AppKit
import SwiftUI
import TopophanyKit

struct PanelShortcutSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(PanelShortcutController.self) private var controller

    var body: some View {
        Section {
            HStack {
                RowLabel("Toggle panel", "Open or close the panel from any app")
                Spacer(minLength: 12)
                ShortcutRecorder(controller: controller) { candidate in
                    model.update { $0.panelShortcut = candidate }
                }
                .frame(width: 154, height: 28)
                Button {
                    controller.cancelRecording()
                    model.update { $0.panelShortcut = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(model.settings.panelShortcut == nil)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
            if let issue = controller.issue {
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("panelShortcutIssue")
            }
        } header: {
            Text("Keyboard shortcut")
        } footer: {
            Foot("Click to record; Esc cancels. Checks system shortcuts and registered global shortcuts. Other apps’ internal shortcuts cannot all be checked.")
        }
    }
}

/// A native, focusable recorder. The local monitor consumes Command keys
/// before menu actions, and only while this button owns keyboard focus.
struct ShortcutRecorder: NSViewRepresentable {
    var controller: PanelShortcutController
    var onRecord: (PanelShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.controller = controller
        button.onRecord = onRecord
        button.refreshTitle()
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        // Read observable values here so the native title follows edits.
        _ = controller.shortcut
        _ = controller.isRecording
        button.onRecord = onRecord
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.endRecording()
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    weak var controller: PanelShortcutController?
    var onRecord: ((PanelShortcut) -> Void)?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        setAccessibilityIdentifier("panelShortcutRecorder")
        setAccessibilityLabel(tr("Toggle panel shortcut"))
        toolTip = tr("Click to record a keyboard shortcut")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit { endRecording() }

    override var acceptsFirstResponder: Bool { true }

    func refreshTitle() {
        title = controller?.isRecording == true ? tr("Press shortcut…") : controller?.shortcut?.display ?? tr("Record shortcut…")
        setAccessibilityValue(title)
    }

    @objc func startRecording() {
        guard let controller, let window else { return }
        if controller.isRecording { endRecording(); return }
        guard window.makeFirstResponder(self) else { return }
        controller.beginRecording()
        refreshTitle()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { self?.capture(event) == true }
            return handled ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endRecording() }
        }
    }

    private func capture(_ event: NSEvent) -> Bool {
        guard controller?.isRecording == true else { return false }
        guard event.window === window, window?.firstResponder === self else {
            endRecording()
            return false
        }
        if event.type != .keyDown {
            if !bounds.contains(convert(event.locationInWindow, from: nil)) { endRecording() }
            return false
        }
        guard !event.isARepeat else { return true }
        let modifiers = PanelShortcut.Modifiers(eventFlags: event.modifierFlags)
        if event.keyCode == 53 { endRecording(); return true }
        if event.keyCode == 48 && modifiers.intersection([.command, .option, .control]).isEmpty {
            endRecording()
            return false
        }
        let candidate = PanelShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        if controller?.record(candidate) == true {
            onRecord?(candidate)
            endRecording()
        }
        refreshTitle()
        return true
    }

    func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        controller?.cancelRecording()
        refreshTitle()
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
}

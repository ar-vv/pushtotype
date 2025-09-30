import AppKit
import Carbon.HIToolbox

final class AccessibilityTextInjector: @unchecked Sendable {
    static let shared = AccessibilityTextInjector()

    private init() {}

    func pasteFromClipboard() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        let location = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: location)
        keyUp?.post(tap: location)
    }
}

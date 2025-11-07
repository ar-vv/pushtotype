import AppKit
import Carbon.HIToolbox

final class AccessibilityTextInjector: @unchecked Sendable {
    static let shared = AccessibilityTextInjector()

    private init() {}

    func pasteFromClipboard(sendEnter: Bool) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        let location = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: location)
        keyUp?.post(tap: location)
        
        // По запросу — добавить небольшую задержку и отправить Enter
        if sendEnter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.sendEnterKey()
            }
        }
    }
    
    private func sendEnterKey() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        
        let location = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: location)
        keyUp?.post(tap: location)
    }
}

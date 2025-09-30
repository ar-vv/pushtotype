import AppKit

final class ClipboardManager: @unchecked Sendable {
    static let shared = ClipboardManager()

    private init() {}

    func store(string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

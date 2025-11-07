import Foundation
import Carbon.HIToolbox

final class HotkeyStorage: @unchecked Sendable {
    static let shared = HotkeyStorage()

    private enum Keys {
        static let mainKeyCode = "hk_main_keycode"            // Транскрибация + автоотправка
        static let mainModifiers = "hk_main_mod"
        static let transcribeKeyCode = "hk_t_keycode"          // Транскрибация (без Enter)
        static let transcribeModifiers = "hk_t_mod"
        static let askKeyCode = "hk_ask_keycode"              // Вопрос (чат)
        static let askModifiers = "hk_ask_mod"
    }

    private let defaults = UserDefaults.standard

    var mainHotkey: Hotkey {
        get {
            let code = defaults.object(forKey: Keys.mainKeyCode) as? UInt16 ?? UInt16(kVK_ANSI_V)
            let modsRaw = defaults.object(forKey: Keys.mainModifiers) as? Int ?? (1 << 0) // Ctrl
            return Hotkey(keyCode: CGKeyCode(code), modifiers: .init(rawValue: modsRaw))
        }
        set {
            defaults.set(UInt16(newValue.keyCode), forKey: Keys.mainKeyCode)
            defaults.set(newValue.modifiers.rawValue, forKey: Keys.mainModifiers)
        }
    }

    // Транскрибация (без Enter)
    var transcribeHotkey: Hotkey {
        get {
            let code = defaults.object(forKey: Keys.transcribeKeyCode) as? UInt16 ?? UInt16(kVK_ANSI_B)
            let modsRaw = defaults.object(forKey: Keys.transcribeModifiers) as? Int ?? (1 << 0) // Ctrl
            return Hotkey(keyCode: CGKeyCode(code), modifiers: .init(rawValue: modsRaw))
        }
        set {
            defaults.set(UInt16(newValue.keyCode), forKey: Keys.transcribeKeyCode)
            defaults.set(newValue.modifiers.rawValue, forKey: Keys.transcribeModifiers)
        }
    }

    // Вопрос (чат)
    var askHotkey: Hotkey {
        get {
            let code = defaults.object(forKey: Keys.askKeyCode) as? UInt16 ?? UInt16(kVK_ANSI_Q)
            let modsRaw = defaults.object(forKey: Keys.askModifiers) as? Int ?? (1 << 0) // Ctrl
            return Hotkey(keyCode: CGKeyCode(code), modifiers: .init(rawValue: modsRaw))
        }
        set {
            defaults.set(UInt16(newValue.keyCode), forKey: Keys.askKeyCode)
            defaults.set(newValue.modifiers.rawValue, forKey: Keys.askModifiers)
        }
    }
}









import Foundation
import Carbon.HIToolbox

final class HotkeyStorage: @unchecked Sendable {
    static let shared = HotkeyStorage()

    private enum Keys {
        static let mainKeyCode = "hk_main_keycode"
        static let mainModifiers = "hk_main_mod"
        static let questionKeyCode = "hk_q_keycode"
        static let questionModifiers = "hk_q_mod"
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

    var questionHotkey: Hotkey {
        get {
            let code = defaults.object(forKey: Keys.questionKeyCode) as? UInt16 ?? UInt16(kVK_ANSI_B)
            let modsRaw = defaults.object(forKey: Keys.questionModifiers) as? Int ?? (1 << 0) // Ctrl
            return Hotkey(keyCode: CGKeyCode(code), modifiers: .init(rawValue: modsRaw))
        }
        set {
            defaults.set(UInt16(newValue.keyCode), forKey: Keys.questionKeyCode)
            defaults.set(newValue.modifiers.rawValue, forKey: Keys.questionModifiers)
        }
    }
}



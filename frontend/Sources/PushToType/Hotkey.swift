import Foundation
import Cocoa
import Carbon.HIToolbox

struct Hotkey: Codable, Equatable {
    struct Modifiers: OptionSet, Codable, Equatable {
        let rawValue: Int

        static let control = Modifiers(rawValue: 1 << 0)
        static let option  = Modifiers(rawValue: 1 << 1)
        static let shift   = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) { self.rawValue = rawValue }

        init(from flags: CGEventFlags) {
            var value = 0
            if flags.contains(.maskControl) { value |= Modifiers.control.rawValue }
            if flags.contains(.maskAlternate) { value |= Modifiers.option.rawValue }
            if flags.contains(.maskShift) { value |= Modifiers.shift.rawValue }
            if flags.contains(.maskCommand) { value |= Modifiers.command.rawValue }
            self.init(rawValue: value)
        }
    }

    let keyCode: CGKeyCode
    let modifiers: Modifiers

    func matches(flags: CGEventFlags, keyCode: CGKeyCode) -> Bool {
        return self.keyCode == keyCode && self.modifiers == Modifiers(from: flags)
    }

    func displayString() -> String {
        // macOS-стиль: ⌃ ⌥ ⇧ ⌘ + key
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        return prefix + keyDisplayName(from: keyCode)
    }

    private func keyDisplayName(from keyCode: CGKeyCode) -> String {
        // Простое отображение для латинских букв и некоторых специальных клавиш
        switch keyCode {
        case CGKeyCode(kVK_ANSI_A): return "A"
        case CGKeyCode(kVK_ANSI_B): return "B"
        case CGKeyCode(kVK_ANSI_C): return "C"
        case CGKeyCode(kVK_ANSI_D): return "D"
        case CGKeyCode(kVK_ANSI_E): return "E"
        case CGKeyCode(kVK_ANSI_F): return "F"
        case CGKeyCode(kVK_ANSI_G): return "G"
        case CGKeyCode(kVK_ANSI_H): return "H"
        case CGKeyCode(kVK_ANSI_I): return "I"
        case CGKeyCode(kVK_ANSI_J): return "J"
        case CGKeyCode(kVK_ANSI_K): return "K"
        case CGKeyCode(kVK_ANSI_L): return "L"
        case CGKeyCode(kVK_ANSI_M): return "M"
        case CGKeyCode(kVK_ANSI_N): return "N"
        case CGKeyCode(kVK_ANSI_O): return "O"
        case CGKeyCode(kVK_ANSI_P): return "P"
        case CGKeyCode(kVK_ANSI_Q): return "Q"
        case CGKeyCode(kVK_ANSI_R): return "R"
        case CGKeyCode(kVK_ANSI_S): return "S"
        case CGKeyCode(kVK_ANSI_T): return "T"
        case CGKeyCode(kVK_ANSI_U): return "U"
        case CGKeyCode(kVK_ANSI_V): return "V"
        case CGKeyCode(kVK_ANSI_W): return "W"
        case CGKeyCode(kVK_ANSI_X): return "X"
        case CGKeyCode(kVK_ANSI_Y): return "Y"
        case CGKeyCode(kVK_ANSI_Z): return "Z"
        case CGKeyCode(kVK_Space): return "Space"
        case CGKeyCode(kVK_Tab): return "Tab"
        case CGKeyCode(kVK_Return): return "Return"
        default:
            return "KeyCode \(keyCode)"
        }
    }
}



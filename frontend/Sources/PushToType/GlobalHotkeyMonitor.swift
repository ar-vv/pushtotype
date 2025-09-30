import Cocoa
import Carbon.HIToolbox

final class GlobalHotkeyMonitor: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onQuestionHotkeyDown: (() -> Void)?
    var onQuestionHotkeyUp: (() -> Void)?

    // Текущие хоткеи (по умолчанию Ctrl+V для основной, Ctrl+B для вопроса)
    var mainHotkey: Hotkey = Hotkey(keyCode: CGKeyCode(kVK_ANSI_V), modifiers: .init(rawValue: 1 << 0)) // Ctrl+V
    var questionHotkey: Hotkey = Hotkey(keyCode: CGKeyCode(kVK_ANSI_B), modifiers: .init(rawValue: 1 << 0)) // Ctrl+B

    // Режим захвата нового сочетания для конкретной функции
    enum CaptureTarget { case main, question }
    private var isCapturing: Bool = false
    private var captureTarget: CaptureTarget = .main
    var onCaptureFinished: ((CaptureTarget, Hotkey) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var activeTarget: CaptureTarget? = nil

    // Состояние захвата: фиксируем комбинацию после полного отпускания всех клавиш
    private var captureObservedKey: CGKeyCode?
    private var captureModifiersAtKeyDown: Hotkey.Modifiers = []
    private var captureKeyReleased: Bool = false

    func start() {
        guard eventTap == nil else { return }
        let eventsMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(eventsMask),
                                          callback: { proxy, type, event, refcon in
                                            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                                            return monitor.handle(proxy: proxy, type: type, event: event)
                                          },
                                          userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())) else {
            NSLog("Failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let modifiers = Hotkey.Modifiers(from: flags)

        // Режим захвата: накапливаем модификаторы на момент нажатия основной клавиши
        if isCapturing {
            if type == .keyDown {
                if !isModifierKey(keyCode) {
                    captureObservedKey = keyCode
                    captureModifiersAtKeyDown = modifiers
                    captureKeyReleased = false
                }
            } else if type == .keyUp {
                if let observed = captureObservedKey, keyCode == observed {
                    captureKeyReleased = true
                }
            }

            // Завершение: основная клавиша отпущена И модификаторы отпущены (flags пустые)
            if captureKeyReleased && Hotkey.Modifiers(from: flags).rawValue == 0 {
                if let finalKey = captureObservedKey {
                    let captured = Hotkey(keyCode: finalKey, modifiers: captureModifiersAtKeyDown)
                    let target = captureTarget
                    // reset
                    isCapturing = false
                    captureObservedKey = nil
                    captureModifiersAtKeyDown = []
                    captureKeyReleased = false
                    Task { @MainActor [weak self] in
                        self?.onCaptureFinished?(target, captured)
                    }
                }
                return Unmanaged.passUnretained(event)
            }

            return Unmanaged.passUnretained(event)
        }

        let isMain = mainHotkey.matches(flags: flags, keyCode: keyCode)
        let isQuestion = questionHotkey.matches(flags: flags, keyCode: keyCode)

        if type == .keyDown && isMain && !isPressed {
            isPressed = true
            activeTarget = .main
            Task { @MainActor [weak self] in
                self?.onHotkeyDown?()
            }
        }

        if type == .keyUp && isPressed && activeTarget == .main && keyCode == mainHotkey.keyCode {
            isPressed = false
            activeTarget = nil
            Task { @MainActor [weak self] in
                self?.onHotkeyUp?()
            }
        }

        // Обработка режима вопроса по аналогии с удержанием
        if type == .keyDown && isQuestion && !isPressed {
            isPressed = true
            activeTarget = .question
            Task { @MainActor [weak self] in
                self?.onQuestionHotkeyDown?()
            }
        }

        if type == .keyUp && isPressed && activeTarget == .question && keyCode == questionHotkey.keyCode {
            isPressed = false
            activeTarget = nil
            Task { @MainActor [weak self] in
                self?.onQuestionHotkeyUp?()
            }
        }

        // Если пользователь отпустил обязательный модификатор — завершаем текущую активность
        if type == .flagsChanged && isPressed {
            switch activeTarget {
            case .main:
                if !requiredModifiers(mainHotkey.modifiers, containedIn: flags) {
                    isPressed = false
                    activeTarget = nil
                    Task { @MainActor [weak self] in
                        self?.onHotkeyUp?()
                    }
                }
            case .question:
                if !requiredModifiers(questionHotkey.modifiers, containedIn: flags) {
                    isPressed = false
                    activeTarget = nil
                    Task { @MainActor [weak self] in
                        self?.onQuestionHotkeyUp?()
                    }
                }
            case .none:
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // Публичный API: старт захвата новой комбинации для указанной цели
    func beginCapture(for target: CaptureTarget) {
        isCapturing = true
        captureTarget = target
        captureObservedKey = nil
        captureModifiersAtKeyDown = []
        captureKeyReleased = false
    }

    private func requiredModifiers(_ required: Hotkey.Modifiers, containedIn flags: CGEventFlags) -> Bool {
        let current = Hotkey.Modifiers(from: flags)
        // Требуемые модификаторы должны быть подмножеством текущих (а не строго равны)
        return (current.rawValue & required.rawValue) == required.rawValue
    }

    private func isModifierKey(_ keyCode: CGKeyCode) -> Bool {
        let mods: [CGKeyCode] = [
            CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand),
            CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift),
            CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption),
            CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl)
        ]
        return mods.contains(keyCode)
    }
}

import Cocoa
import Carbon.HIToolbox

final class GlobalHotkeyMonitor: @unchecked Sendable {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onTranscribeHotkeyDown: (() -> Void)?
    var onTranscribeHotkeyUp: (() -> Void)?
    var onAskHotkeyDown: (() -> Void)?
    var onAskHotkeyUp: (() -> Void)?
    var onCaptureFinished: ((CaptureTarget, Hotkey) -> Void)?

    enum CaptureTarget {
        case main
        case transcribe
        case ask
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var captureTarget: CaptureTarget?

    func start() {
        guard eventTap == nil else { return }
        let eventsMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
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

    func beginCapture(_ target: CaptureTarget) {
        captureTarget = target
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Режим захвата: любая клавиша сохраняет хоткей с текущими модификаторами
        if type == .keyDown, let target = captureTarget {
            let captured = Hotkey(keyCode: keyCode, modifiers: .init(from: flags))
            captureTarget = nil
            Task { @MainActor [weak self] in
                self?.onCaptureFinished?(target, captured)
            }
            return Unmanaged.passUnretained(event)
        }

        // Сопоставление с сохранёнными хоткеями
        let mainHK = HotkeyStorage.shared.mainHotkey            // с Enter
        let tHK = HotkeyStorage.shared.transcribeHotkey        // без Enter
        let aHK = HotkeyStorage.shared.askHotkey               // вопрос

        if type == .keyDown && mainHK.matches(flags: flags, keyCode: keyCode) && !isPressed {
            isPressed = true
            Task { @MainActor [weak self] in
                self?.onHotkeyDown?()
            }
        }

        if type == .keyUp && isPressed && mainHK.matches(flags: flags, keyCode: keyCode) {
            isPressed = false
            Task { @MainActor [weak self] in
                self?.onHotkeyUp?()
            }
        }

        if type == .keyDown && tHK.matches(flags: flags, keyCode: keyCode) && !isPressed {
            isPressed = true
            Task { @MainActor [weak self] in
                self?.onTranscribeHotkeyDown?()
            }
        }

        if type == .keyUp && isPressed && tHK.matches(flags: flags, keyCode: keyCode) {
            isPressed = false
            Task { @MainActor [weak self] in
                self?.onTranscribeHotkeyUp?()
            }
        }

        if type == .keyDown && aHK.matches(flags: flags, keyCode: keyCode) && !isPressed {
            isPressed = true
            Task { @MainActor [weak self] in
                self?.onAskHotkeyDown?()
            }
        }

        if type == .keyUp && isPressed && aHK.matches(flags: flags, keyCode: keyCode) {
            isPressed = false
            Task { @MainActor [weak self] in
                self?.onAskHotkeyUp?()
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

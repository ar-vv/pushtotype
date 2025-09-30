import AppKit
import AVFoundation
import ApplicationServices

final class PermissionsManager: @unchecked Sendable {
    static let shared = PermissionsManager()
    
    private init() {}
    
    // MARK: - Microphone Permissions
    
    var isMicrophoneGranted: Bool {
        // На macOS разрешение на микрофон запрашивается автоматически при первом использовании AVAudioRecorder
        // Проверяем через создание временного recorder
        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
            let canRecord = recorder.prepareToRecord()
            try? FileManager.default.removeItem(at: tempURL)
            return canRecord
        } catch {
            return false
        }
    }
    
    @MainActor
    func requestMicrophonePermission() {
        let alert = NSAlert()
        alert.messageText = "Разрешение на микрофон"
        alert.informativeText = "Для записи аудио приложению PushToType требуется доступ к микрофону. Пожалуйста, разрешите доступ в Системных настройках > Конфиденциальность и безопасность > Микрофон."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Отмена")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Accessibility Permissions
    
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    
    @MainActor
    func requestAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = "Разрешение на Accessibility"
        alert.informativeText = "Для вставки текста в активное окно приложению PushToType требуется доступ к Accessibility. Пожалуйста, разрешите доступ в Системных настройках > Конфиденциальность и безопасность > Универсальный доступ."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Отмена")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Status Text
    
    func getPermissionsStatusText() -> String {
        let micStatus = isMicrophoneGranted ? "✅" : "❌"
        let accessibilityStatus = isAccessibilityGranted ? "✅" : "❌"
        return "\(micStatus) Микрофон \(accessibilityStatus) Accessibility"
    }
}

import Foundation

@MainActor
final class AudioStorage: @unchecked Sendable {
    static let shared = AudioStorage()
    
    private let documentsURL: URL
    private let lastRecordingFileName = "last_recording.m4a"
    
    private init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    var lastRecordingURL: URL {
        documentsURL.appendingPathComponent(lastRecordingFileName)
    }
    
    var hasLastRecording: Bool {
        FileManager.default.fileExists(atPath: lastRecordingURL.path)
    }
    
    func saveRecording(from sourceURL: URL) throws {
        // Удаляем старую запись если есть
        if hasLastRecording {
            try? FileManager.default.removeItem(at: lastRecordingURL)
        }
        
        // Копируем новую запись
        try FileManager.default.copyItem(at: sourceURL, to: lastRecordingURL)
        print("✅ Аудиозапись сохранена: \(lastRecordingURL.path)")
    }
    
    func clearLastRecording() {
        if hasLastRecording {
            try? FileManager.default.removeItem(at: lastRecordingURL)
            print("🗑️ Последняя запись удалена")
        }
    }
}








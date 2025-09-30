import AVFoundation

@MainActor
final class AudioRecorder: @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func startRecording() throws -> URL {
        if let recorder, recorder.isRecording {
            return recorder.url
        }

        let url = makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000, // Changed from 44_100
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        recorder.record()

        self.recorder = recorder
        currentURL = url
        return url
    }

    func stopRecording() -> URL? {
        guard let recorder else { return currentURL }
        recorder.stop()
        self.recorder = nil
        let url = currentURL
        currentURL = nil
        return url
    }

    private func makeRecordingURL() -> URL {
        let filename = "recording-\(UUID().uuidString).m4a"
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent(filename)
    }
}
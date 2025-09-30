import Foundation

final class BackendClient: @unchecked Sendable {
    struct ChatResponse: Decodable {
        let answer: String
    }
    private struct UploadResponse: Decodable {
        let recording_id: String
    }

    private struct TranscriptionResponse: Decodable {
        let status: String
        let transcription: String?
        let error: String? // NEW
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? Configuration.shared.backendBaseURL
        self.session = session
        print("[BackendClient] baseURL=\(self.baseURL.absoluteString)")
        // Диагностика: записываем текущий baseURL в файл
        let diagPath = URL(fileURLWithPath: "/tmp/pushtotype_baseurl.txt")
        try? (self.baseURL.absoluteString + "\n").data(using: .utf8)?.write(to: diagPath)
    }

    func uploadAudio(fileURL: URL, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        let uploadURL = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("audio")
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Иногда файл ещё не полностью финализирован сразу после stop().
        // Сделаем несколько попыток прочитать его с короткой задержкой.
        var audioData: Data?
        for attempt in 1...5 {
            if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
                audioData = data
                break
            }
            usleep(100_000) // 100ms
        }
        guard let audioData else {
            completion(.failure(NSError(domain: "PushToType", code: -1, userInfo: [NSLocalizedDescriptionKey: "Файл пуст или недоступен"])));
            return
        }
        PTLog.write("upload start file=\(fileURL.lastPathComponent) size=\(audioData.count) to=\(uploadURL.absoluteString)")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let filename = fileURL.lastPathComponent.isEmpty ? "audio.m4a" : fileURL.lastPathComponent
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error {
                PTLog.write("upload error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? "<no body>"
                PTLog.write("upload http=\(http.statusCode) body=\(body)")
                completion(.failure(NSError(domain: "PushToType", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки аудио (HTTP \(http.statusCode))"])))
                return
            }

            guard let data else {
                completion(.failure(NSError(domain: "PushToType", code: -2, userInfo: [NSLocalizedDescriptionKey: "Пустой ответ"])))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
                PTLog.write("upload success id=\(decoded.recording_id)")
                completion(.success(decoded.recording_id))
            } catch {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                PTLog.write("upload decode error: \(error). body=\(body)")
                completion(.failure(error))
            }
        }.resume()
    }

    func pollTranscription(recordingId: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        let poller = TranscriptionPoller(baseURL: baseURL, session: session)
        poller.startPolling(recordingId: recordingId, completion: completion)
    }

    private final class TranscriptionPoller: @unchecked Sendable {
        private let baseURL: URL
        private let session: URLSession
        private var timer: Timer?
        private let initialPollingInterval: TimeInterval = 0.1  // 100ms
        private var currentPollingInterval: TimeInterval = 0.1
        private let maxPollingInterval: TimeInterval = 5.0     // Максимум 5 секунд
        private let backoffMultiplier: Double = 1.5            // Увеличение в 1.5 раза
        private let timeout: TimeInterval
        private var startDate = Date()
        private var completion: (@Sendable (Result<String, Error>) -> Void)?
        private var recordingId: String = ""

        init(baseURL: URL, session: URLSession) {
            self.baseURL = baseURL
            self.session = session
            self.timeout = Configuration.shared.timeout
        }

        func startPolling(recordingId: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
            self.recordingId = recordingId
            self.completion = completion
            self.currentPollingInterval = initialPollingInterval
            startDate = Date()
            scheduleNextPoll()
        }
        
        private func scheduleNextPoll() {
            DispatchQueue.main.async {
                self.timer = Timer.scheduledTimer(timeInterval: self.currentPollingInterval,
                                                  target: self,
                                                  selector: #selector(self.handleTimer),
                                                  userInfo: nil,
                                                  repeats: false)
            }
        }

        @objc private func handleTimer() {
            if Date().timeIntervalSince(startDate) > timeout {
                finish(with: .failure(NSError(domain: "PushToType", code: -3, userInfo: [NSLocalizedDescriptionKey: "Таймаут"])))
                return
            }

            let url = baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("transcription")
                .appendingPathComponent(recordingId)
            session.dataTask(with: url) { data, response, error in
                if let error {
                    PTLog.write("poll error: \(error.localizedDescription)")
                    self.finish(with: .failure(error))
                    return
                }

                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 404 {
                        PTLog.write("poll 404 for \(url.absoluteString)")
                        self.finish(with: .failure(NSError(domain: "PushToType", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown job (404)"])) )
                        return
                    }
                    if !(200...299).contains(http.statusCode) {
                        PTLog.write("poll HTTP=\(http.statusCode)")
                        self.increasePollingInterval()
                        self.scheduleNextPoll()
                        return
                    }
                }

                guard let data else {
                    // Увеличиваем интервал и планируем следующий запрос
                    self.increasePollingInterval()
                    self.scheduleNextPoll()
                    return
                }

                guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    PTLog.write("poll decode fail body=\(body)")
                    // Увеличиваем интервал и планируем следующий запрос
                    self.increasePollingInterval()
                    self.scheduleNextPoll()
                    return
                }

                if decoded.status.lowercased() == "ready", let transcription = decoded.transcription {
                    PTLog.write("poll ready, len=\(transcription.count)")
                    self.finish(with: .success(transcription))
                } else if decoded.status.lowercased() == "error" {
                    let message = decoded.error ?? "Неизвестная ошибка транскрибации"
                    PTLog.write("poll error status: \(message)")
                    self.finish(with: .failure(NSError(domain: "PushToType", code: -4, userInfo: [NSLocalizedDescriptionKey: message])))
                } else {
                    PTLog.write("poll processing")
                    // Статус "processing" - увеличиваем интервал и планируем следующий запрос
                    self.increasePollingInterval()
                    self.scheduleNextPoll()
                }
            }.resume()
        }
        
        private func increasePollingInterval() {
            currentPollingInterval = min(currentPollingInterval * backoffMultiplier, maxPollingInterval)
        }

        private func finish(with result: Result<String, Error>) {
            DispatchQueue.main.async {
                self.timer?.invalidate()
                self.timer = nil
                self.completion?(result)
                self.completion = nil
            }
        }
    }

    func askChatGPT(question: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = ["question": question]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(NSError(domain: "PushToType", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка GPT (HTTP \(http.statusCode))"])))
                return
            }
            guard let data else {
                completion(.failure(NSError(domain: "PushToType", code: -5, userInfo: [NSLocalizedDescriptionKey: "Пустой ответ GPT"])) )
                return
            }
            do {
                let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
                completion(.success(decoded.answer))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

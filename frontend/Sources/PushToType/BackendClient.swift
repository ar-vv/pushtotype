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

    @discardableResult
    func uploadAudio(fileURL: URL, completion: @escaping @Sendable (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        let uploadURL = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("audio")
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let audioData = try? Data(contentsOf: fileURL) else {
            completion(.failure(NSError(domain: "PushToType", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать файл"])));
            return nil
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                #if DEBUG
                print("[BackendClient] upload error to \(uploadURL): \(error.localizedDescription)")
                #endif
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                #if DEBUG
                print("[BackendClient] upload HTTP error \(http.statusCode) for \(uploadURL)")
                #endif
                completion(.failure(NSError(domain: "PushToType", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки аудио (HTTP \(http.statusCode))"])))
                return
            }

            guard let data else {
                completion(.failure(NSError(domain: "PushToType", code: -2, userInfo: [NSLocalizedDescriptionKey: "Пустой ответ"])))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
                completion(.success(decoded.recording_id))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }

    @discardableResult
    func pollTranscription(recordingId: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) -> TranscriptionPoller {
        let poller = TranscriptionPoller(baseURL: baseURL, session: session)
        poller.startPolling(recordingId: recordingId, completion: completion)
        return poller
    }

    final class TranscriptionPoller: @unchecked Sendable {
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
        private var isCancelled = false

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

        func cancel() {
            DispatchQueue.main.async {
                self.isCancelled = true
                self.timer?.invalidate()
                self.timer = nil
                self.completion = nil
            }
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
            if isCancelled { return }
            if Date().timeIntervalSince(startDate) > timeout {
                finish(with: .failure(NSError(domain: "PushToType", code: -3, userInfo: [NSLocalizedDescriptionKey: "Таймаут"])))
                return
            }

            let url = baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("transcription")
                .appendingPathComponent(recordingId)
            session.dataTask(with: url) { data, response, error in
                if self.isCancelled { return }
                if let error {
                    #if DEBUG
                    print("[BackendClient] poll error from \(url): \(error.localizedDescription)")
                    #endif
                    self.finish(with: .failure(error))
                    return
                }

                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 404 {
                        #if DEBUG
                        print("[BackendClient] poll 404 for \(url)")
                        #endif
                        self.finish(with: .failure(NSError(domain: "PushToType", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown job (404)"])) )
                        return
                    }
                    if !(200...299).contains(http.statusCode) {
                        #if DEBUG
                        print("[BackendClient] poll HTTP \(http.statusCode) for \(url)")
                        #endif
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
                    // Увеличиваем интервал и планируем следующий запрос
                    self.increasePollingInterval()
                    self.scheduleNextPoll()
                    return
                }

                if decoded.status.lowercased() == "ready", let transcription = decoded.transcription {
                    self.finish(with: .success(transcription))
                } else if decoded.status.lowercased() == "error" {
                    let message = decoded.error ?? "Неизвестная ошибка транскрибации"
                    #if DEBUG
                    print("[BackendClient] transcription error: \(message)")
                    #endif
                    self.finish(with: .failure(NSError(domain: "PushToType", code: -4, userInfo: [NSLocalizedDescriptionKey: message])))
                } else {
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

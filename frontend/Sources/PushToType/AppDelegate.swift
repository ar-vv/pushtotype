import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private let hotkeyMonitor = GlobalHotkeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let backendClient = BackendClient()
    private let statusHUD = StatusHUDController()
    private let chatWeb = ChatWebViewController()
    
    private enum RecordingAction {
        case sendEnter
        case noEnter
        case ask
    }
    private var currentAction: RecordingAction = .sendEnter

    private var currentRecordingURL: URL?
    private var isRequestingAccessibility = false
    private var currentUploadTask: URLSessionDataTask?
    private var currentPoller: BackendClient.TranscriptionPoller?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        configureHotkeyCallbacks()
        statusHUD.onCancel = { [weak self] in
            self?.cancelCurrentFlow()
        }
        requestMicrophoneAccess()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor.stop()
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController { [weak self] in
            self?.statusHUD.revealTemporarily()
        } onQuit: {
            NSApp.terminate(nil)
        }

        // Подключаем обработчик пункта меню "Транскрипция последней записи"
        statusBarController.onRetryLastRecording = { [weak self] in
            self?.processLastRecording()
        }

        // Подключаем обработчик пункта меню "Добавить файл…"
        statusBarController.onSelectAudioFile = { [weak self] in
            self?.selectAndTranscribeFile()
        }

        // Подключаем захват хоткеев
        statusBarController.onChangeMainHotkey = { [weak self] in
            guard let self else { return }
            self.statusHUD.showNotice(title: "Задайте сочетание", detail: "Нажмите новое сочетание для основной функции")
            self.hotkeyMonitor.beginCapture(.main)
        }

        statusBarController.onChangeTranscribeHotkey = { [weak self] in
            guard let self else { return }
            self.statusHUD.showNotice(title: "Задайте сочетание", detail: "Нажмите новое сочетание для транскрибации без Enter")
            self.hotkeyMonitor.beginCapture(.transcribe)
        }

        statusBarController.onChangeAskHotkey = { [weak self] in
            guard let self else { return }
            self.statusHUD.showNotice(title: "Задайте сочетание", detail: "Нажмите новое сочетание для режима Вопрос")
            self.hotkeyMonitor.beginCapture(.ask)
        }
    }

    private func configureHotkeyCallbacks() {
        // Сохранение результатов захвата хоткеев
        hotkeyMonitor.onCaptureFinished = { [weak self] target, hotkey in
            switch target {
            case .main:
                HotkeyStorage.shared.mainHotkey = hotkey
            case .transcribe:
                HotkeyStorage.shared.transcribeHotkey = hotkey
            case .ask:
                HotkeyStorage.shared.askHotkey = hotkey
            }
            Task { @MainActor [weak self] in
                self?.statusBarController.updateMenu()
                self?.statusHUD.showNotice(title: "Готово", detail: "Горячая клавиша обновлена")
            }
        }

        hotkeyMonitor.onHotkeyDown = { [weak self] in
            self?.currentAction = .sendEnter
            self?.beginRecording()
        }

        hotkeyMonitor.onHotkeyUp = { [weak self] in
            self?.finishRecording()
        }

        hotkeyMonitor.onTranscribeHotkeyDown = { [weak self] in
            self?.currentAction = .noEnter
            self?.beginRecording()
        }

        hotkeyMonitor.onTranscribeHotkeyUp = { [weak self] in
            self?.finishRecording()
        }

        hotkeyMonitor.onAskHotkeyDown = { [weak self] in
            self?.currentAction = .ask
            self?.beginRecording()
        }

        hotkeyMonitor.onAskHotkeyUp = { [weak self] in
            self?.finishRecording()
        }

        hotkeyMonitor.start()

    }

    private func beginRecording() {
        guard currentRecordingURL == nil else { return }
        statusHUD.update(stage: .recording)

        do {
            let url = try audioRecorder.startRecording()
            currentRecordingURL = url
        } catch {
            statusHUD.update(stage: .error("Не удалось начать запись"))
            currentRecordingURL = nil
        }
    }

    private func finishRecording() {
        // Небольшая задержка, чтобы AVAudioRecorder успел финализировать файл
        guard let recordingURL = audioRecorder.stopRecording() ?? currentRecordingURL else {
            currentRecordingURL = nil
            return
        }

        currentRecordingURL = nil
        // Сохраняем запись локально для повтора
        do {
            try AudioStorage.shared.saveRecording(from: recordingURL)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: recordingURL.path),
               let size = attrs[.size] as? NSNumber {
                PTLog.write("saved recording size=\(size.intValue) path=\(recordingURL.lastPathComponent)")
            }
        } catch {
            // Не блокируем процесс, но обновим HUD
            statusHUD.update(stage: .error("Не удалось сохранить запись для повтора"))
        }
        // Обновляем меню, чтобы активировать пункт повтора
        statusBarController.updateMenu()

        statusHUD.update(stage: .uploading)

        // Дадим системе финализировать файл
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.currentUploadTask = self.backendClient.uploadAudio(fileURL: recordingURL) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let recordingId):
                        PTLog.write("upload ok id=\(recordingId)")
                        self?.handleUploadSuccess(recordingId: recordingId)
                    case .failure(let error):
                        PTLog.write("upload fail: \(error.localizedDescription)")
                        self?.statusHUD.update(stage: .error(error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Открыть диалог выбора аудиофайла и отправить на транскрибацию
    private func selectAndTranscribeFile() {
        let panel = NSOpenPanel()
        panel.message = "Выберите аудиофайл для транскрибации"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = [
            // Основные
            "m4a", "mp3", "wav", "aac", "caf",
            // Дополнительно поддерживаемые Whisper/OpenAI
            "mp4", "mpeg", "mpga", "webm", "ogg", "oga", "opus"
        ]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        statusHUD.update(stage: .uploading)

        backendClient.uploadAudio(fileURL: url) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let recordingId):
                    self?.handleUploadSuccess(recordingId: recordingId)
                case .failure(let error):
                    self?.statusHUD.update(stage: .error(error.localizedDescription))
                }
            }
        }
    }

    /// Повторная отправка сохраненной записи без новой записи звука
    private func processLastRecording() {
        guard AudioStorage.shared.hasLastRecording else {
            statusHUD.update(stage: .error("Нет сохраненной записи"))
            return
        }

        statusHUD.update(stage: .uploading)

        let url = AudioStorage.shared.lastRecordingURL
        backendClient.uploadAudio(fileURL: url) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let recordingId):
                    self?.handleUploadSuccess(recordingId: recordingId)
                case .failure(let error):
                    self?.statusHUD.update(stage: .error(error.localizedDescription))
                }
            }
        }
    }

    private func handleUploadSuccess(recordingId: String) {
        statusHUD.update(stage: .waitingForTranscription)

        currentPoller = backendClient.pollTranscription(recordingId: recordingId) { [weak self] pollResult in
            guard let self else { return }
            DispatchQueue.main.async {
                switch pollResult {
                case .success(let transcription):
                    switch self.currentAction {
                    case .ask:
                        self.askChatAndShowAnswer(transcription: transcription)
                    case .noEnter:
                        self.statusHUD.update(stage: .completed)
                        self.pushTranscriptionToUser(transcription, sendEnter: false)
                    case .sendEnter:
                        self.statusHUD.update(stage: .completed)
                        self.pushTranscriptionToUser(transcription, sendEnter: true)
                    }
                case .failure(let error):
                    self.statusHUD.update(stage: .error(error.localizedDescription))
                }
            }
        }
    }

    // Отмена текущего процесса: запись/загрузка/ожидание
    private func cancelCurrentFlow() {
        // Останавливаем запись, если идёт
        _ = audioRecorder.stopRecording()
        currentRecordingURL = nil
        // Отменяем загрузку и поллинг
        currentUploadTask?.cancel()
        currentUploadTask = nil
        currentPoller?.cancel()
        currentPoller = nil
        // Сбрасываем HUD и состояние
        statusHUD.hideImmediately()
        // Сообщаем бэкенду/поллеру прекратить ожидание — через отдельный экземпляр poller пока не поддерживается,
        // поэтому просто сбросим callback: дальнейшие ответы будут игнорироваться, так как self уже не выполнит вставку.
        // Для гарантии: переведём в idle
        statusHUD.update(stage: .idle)
    }

    private func askChatAndShowAnswer(transcription: String) {
        statusHUD.update(stage: .chatResponding)
        backendClient.askChatGPT(question: transcription) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let answer):
                    self?.statusHUD.hideImmediately()
                    self?.chatWeb.show(markdown: answer)
                case .failure(let error):
                    self?.statusHUD.update(stage: .error(error.localizedDescription))
                }
            }
        }
    }

    private func pushTranscriptionToUser(_ transcription: String, sendEnter: Bool) {
        ClipboardManager.shared.store(string: transcription)
        AccessibilityTextInjector.shared.pasteFromClipboard(sendEnter: sendEnter)
    }

    private func requestMicrophoneAccess() {
        // На macOS разрешение на микрофон запрашивается системой при первой записи.
        // Переходим к запросу доступа к Accessibility.
        requestAccessibilityAccessIfNeeded()
    }

    private func requestAccessibilityAccessIfNeeded() {
        guard !isRequestingAccessibility else { return }
        isRequestingAccessibility = true
        // Избегаем обращения к var kAXTrustedCheckOptionPrompt (concurrency-safety)
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            statusHUD.update(stage: .awaitingAccessibility)
        }
    }
}

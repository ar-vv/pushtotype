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
    private var isQuestionMode = false

    private var currentRecordingURL: URL?
    private var isRequestingAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        configureHotkeyCallbacks()
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

        // Обработчики изменения хоткеев
        statusBarController.onChangeMainHotkey = { [weak self] in
            self?.beginHotkeyCapture(target: .main)
        }
        statusBarController.onChangeQuestionHotkey = { [weak self] in
            self?.beginHotkeyCapture(target: .question)
        }
    }

    private func configureHotkeyCallbacks() {
        // Инициализация хоткеев из хранилища
        hotkeyMonitor.mainHotkey = HotkeyStorage.shared.mainHotkey
        hotkeyMonitor.questionHotkey = HotkeyStorage.shared.questionHotkey

        hotkeyMonitor.onHotkeyDown = { [weak self] in
            self?.isQuestionMode = false
            self?.beginRecording()
        }

        hotkeyMonitor.onHotkeyUp = { [weak self] in
            self?.finishRecording()
        }

        hotkeyMonitor.onQuestionHotkeyDown = { [weak self] in
            self?.isQuestionMode = true
            self?.beginRecording()
        }

        hotkeyMonitor.onQuestionHotkeyUp = { [weak self] in
            self?.finishRecording()
        }

        hotkeyMonitor.start()

        // Колбэк завершения захвата комбинации
        hotkeyMonitor.onCaptureFinished = { [weak self] target, hotkey in
            guard let self else { return }
            switch target {
            case .main:
                HotkeyStorage.shared.mainHotkey = hotkey
                self.hotkeyMonitor.mainHotkey = hotkey
            case .question:
                HotkeyStorage.shared.questionHotkey = hotkey
                self.hotkeyMonitor.questionHotkey = hotkey
            }
            self.statusBarController.updateMenu()
            let name = (target == .main) ? "основной функции" : "режима вопроса"
            self.statusHUD.showNotice(title: "Сочетание сохранено",
                                      detail: "Новое сочетание для \(name): \(hotkey.displayString())")
        }
    }

    private func beginHotkeyCapture(target: GlobalHotkeyMonitor.CaptureTarget) {
        switch target {
        case .main:
            statusHUD.showNotice(title: "Задать сочетание", detail: "Нажмите желаемое сочетание для основной функции", autoHide: nil)
        case .question:
            statusHUD.showNotice(title: "Задать сочетание", detail: "Нажмите желаемое сочетание для режима вопроса", autoHide: nil)
        }
        hotkeyMonitor.beginCapture(for: target)
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
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.backendClient.uploadAudio(fileURL: recordingURL) { [weak self] result in
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

        backendClient.pollTranscription(recordingId: recordingId) { [weak self] pollResult in
            guard let self else { return }
            DispatchQueue.main.async {
                switch pollResult {
                case .success(let transcription):
                    if self.isQuestionMode {
                        self.askChatAndShowAnswer(transcription: transcription)
                    } else {
                        self.statusHUD.update(stage: .completed)
                        self.pushTranscriptionToUser(transcription)
                    }
                case .failure(let error):
                    self.statusHUD.update(stage: .error(error.localizedDescription))
                }
            }
        }
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

    private func pushTranscriptionToUser(_ transcription: String) {
        ClipboardManager.shared.store(string: transcription)
        AccessibilityTextInjector.shared.pasteFromClipboard()
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

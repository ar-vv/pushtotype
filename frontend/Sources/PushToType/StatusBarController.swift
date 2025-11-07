import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let onShowStatus: () -> Void
    private let onQuit: () -> Void
    var onChangeMainHotkey: (() -> Void)?          // Транскрибация + автоотправка
    var onChangeTranscribeHotkey: (() -> Void)?    // Транскрибация
    var onChangeAskHotkey: (() -> Void)?           // Вопрос
    var onRetryLastRecording: (() -> Void)?
    var onSelectAudioFile: (() -> Void)?

    

    init(onShowStatus: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShowStatus = onShowStatus
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let symbolImage = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "PushToType") {
            symbolImage.isTemplate = true
            button.image = symbolImage
        } else {
            button.title = "PT"
        }
        button.toolTip = "PushToType - Ctrl+V для записи"
    }

    private func configureMenu() {
        let menu = NSMenu()

        // Заголовок с названием приложения
        let titleItem = NSMenuItem(title: "PushToType", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())

        // Статус разрешений
        let permissionsStatusItem = NSMenuItem(title: "Статус разрешений", action: nil, keyEquivalent: "")
        permissionsStatusItem.isEnabled = false
        menu.addItem(permissionsStatusItem)
        
        // Подробный статус
        let statusText = PermissionsManager.shared.getPermissionsStatusText()
        let detailsItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        detailsItem.isEnabled = false
        menu.addItem(detailsItem)

        // Кнопки для получения разрешений
        let microphoneItem = NSMenuItem(title: "Разрешить микрофон", action: #selector(requestMicrophonePermission), keyEquivalent: "")
        microphoneItem.target = self
        menu.addItem(microphoneItem)
        
        let accessibilityItem = NSMenuItem(title: "Разрешить Accessibility", action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        
        menu.addItem(NSMenuItem.separator())

        // Транскрибация файла
        let fileSectionTitle = NSMenuItem(title: "Транскрибация файла", action: nil, keyEquivalent: "")
        fileSectionTitle.isEnabled = false
        menu.addItem(fileSectionTitle)

        let addFileItem = NSMenuItem(title: "Добавить файл…", action: #selector(selectAudioFile), keyEquivalent: "")
        addFileItem.target = self
        menu.addItem(addFileItem)

        menu.addItem(NSMenuItem.separator())

        // Транскрипция последней записи
        let retryItem = NSMenuItem(title: "Транскрипция последней записи", action: #selector(retryLastRecording), keyEquivalent: "")
        retryItem.target = self
        retryItem.isEnabled = AudioStorage.shared.hasLastRecording
        menu.addItem(retryItem)
        
        menu.addItem(NSMenuItem.separator())

        // Горячие клавиши (отображаем и даем изменить)
        let mainHK = HotkeyStorage.shared.mainHotkey.displayString()
        let tHK = HotkeyStorage.shared.transcribeHotkey.displayString()
        let aHK = HotkeyStorage.shared.askHotkey.displayString()

        let hkTitle = NSMenuItem(title: "Горячие клавиши", action: nil, keyEquivalent: "")
        hkTitle.isEnabled = false
        menu.addItem(hkTitle)

        let mainItem = NSMenuItem(title: "Транскрибация + автоотправка: \(mainHK)", action: nil, keyEquivalent: "")
        mainItem.isEnabled = false
        menu.addItem(mainItem)

        let changeMain = NSMenuItem(title: "Задать…", action: #selector(captureMainHotkey), keyEquivalent: "")
        changeMain.target = self
        menu.addItem(changeMain)

        let tItem = NSMenuItem(title: "Транскрибация: \(tHK)", action: nil, keyEquivalent: "")
        tItem.isEnabled = false
        menu.addItem(tItem)

        let changeT = NSMenuItem(title: "Задать…", action: #selector(captureTranscribeHotkey), keyEquivalent: "")
        changeT.target = self
        menu.addItem(changeT)

        let aItem = NSMenuItem(title: "Вопрос: \(aHK)", action: nil, keyEquivalent: "")
        aItem.isEnabled = false
        menu.addItem(aItem)

        let changeA = NSMenuItem(title: "Задать…", action: #selector(captureAskHotkey), keyEquivalent: "")
        changeA.target = self
        menu.addItem(changeA)

        let instructionItem = NSMenuItem(title: "Удерживайте основную для записи", action: nil, keyEquivalent: "")
        instructionItem.isEnabled = false
        menu.addItem(instructionItem)

        menu.addItem(NSMenuItem.separator())

        // Разделитель перед служебными пунктами
        menu.addItem(NSMenuItem.separator())

        // Показать статус (существующая функция)
        let statusItem = NSMenuItem(title: "Показать HUD", action: #selector(showStatus), keyEquivalent: "")
        statusItem.target = self
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Кнопка закрытия
        let quitItem = NSMenuItem(title: "Закрыть приложение", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }
    
    func updateMenu() {
        configureMenu()
    }

    @objc private func showStatus() {
        onShowStatus()
    }
    
    @objc private func requestMicrophonePermission() {
        PermissionsManager.shared.requestMicrophonePermission()
        updateMenu() // Обновляем меню после запроса разрешения
    }
    
    @objc private func requestAccessibilityPermission() {
        PermissionsManager.shared.requestAccessibilityPermission()
        updateMenu() // Обновляем меню после запроса разрешения
    }
    
    @objc private func retryLastRecording() {
        onRetryLastRecording?()
    }

    @objc private func selectAudioFile() {
        onSelectAudioFile?()
    }

    @objc private func quit() {
        onQuit()
    }

    @objc private func captureMainHotkey() {
        onChangeMainHotkey?()
    }

    @objc private func captureTranscribeHotkey() {
        onChangeTranscribeHotkey?()
    }

    @objc private func captureAskHotkey() {
        onChangeAskHotkey?()
    }

}

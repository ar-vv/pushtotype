import AppKit

@MainActor
final class StatusHUDController: @unchecked Sendable {
    private let panel: NSPanel
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let scrollView: NSScrollView
    private let largeTextView: NSTextView
    private let closeButton: NSButton
    private let retryButton: NSButton
    private let cancelButton: NSButton
    private var hideWorkItem: DispatchWorkItem?
    private let compactWidth: CGFloat = 260
    
    var onRetry: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        let panelSize = NSSize(width: compactWidth, height: 110)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                        styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow],
                        backing: .buffered,
                        defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllApplications, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        panel.alphaValue = 0.0
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.hasShadow = true
        // Убеждаемся, что панель следует системной теме
        panel.appearance = NSAppearance.current

        let content = NSView(frame: NSRect(origin: .zero, size: panelSize))
        panel.contentView = content

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 0
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Большой прокручиваемый вид для ответов GPT
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.isHidden = true

        largeTextView = NSTextView(frame: .zero)
        largeTextView.isEditable = false
        largeTextView.isSelectable = true
        largeTextView.drawsBackground = false
        largeTextView.textContainerInset = NSSize(width: 12, height: 12)
        largeTextView.font = .systemFont(ofSize: 16)
        // Обеспечиваем перенос строк и отсутствие горизонтальной прокрутки
        largeTextView.isRichText = true
        largeTextView.isHorizontallyResizable = false
        largeTextView.isVerticallyResizable = true
        largeTextView.minSize = NSSize(width: 0, height: 0)
        largeTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        largeTextView.textContainer?.widthTracksTextView = true
        largeTextView.textContainer?.lineFragmentPadding = 0
        // Убеждаемся, что текст использует системные цвета для правильного отображения в тёмной теме
        largeTextView.textColor = .labelColor
        scrollView.documentView = largeTextView
        scrollView.contentView.postsBoundsChangedNotifications = true
        // Подписку на изменение размеров контента добавим после инициализации всех полей

        // Создаем кнопку закрытия
        closeButton = NSButton()
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.isBordered = false
        closeButton.title = "✕"
        closeButton.font = .systemFont(ofSize: 14, weight: .medium)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.appearance = NSAppearance.current
        
        // Добавляем hover эффект
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 10
        
        // Создаем кнопку повтора
        retryButton = NSButton()
        retryButton.setButtonType(.momentaryPushIn)
        retryButton.bezelStyle = .rounded
        retryButton.title = "Попробовать еще раз"
        retryButton.font = .systemFont(ofSize: 12)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true // Показывается только при ошибке

        // Кнопка отмены процесса
        cancelButton = NSButton()
        cancelButton.setButtonType(.momentaryPushIn)
        cancelButton.bezelStyle = .rounded
        cancelButton.title = "Отмена"
        cancelButton.font = .systemFont(ofSize: 12)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.isHidden = true
        
        // Настраиваем targets после инициализации всех свойств
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        retryButton.target = self
        retryButton.action = #selector(retryButtonClicked)
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked)
        
        content.addSubview(titleLabel)
        content.addSubview(detailLabel)
        content.addSubview(scrollView)
        content.addSubview(closeButton)
        content.addSubview(retryButton)
        content.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            // Кнопка закрытия в правом верхнем углу
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            
            // Основной контент с отступом от кнопки
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            
            // Кнопки внизу
            retryButton.centerXAnchor.constraint(equalTo: content.centerXAnchor, constant: 60),
            retryButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 12),
            retryButton.heightAnchor.constraint(equalToConstant: 24),

            cancelButton.centerXAnchor.constraint(equalTo: content.centerXAnchor, constant: -60),
            cancelButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 12),
            cancelButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Констрейнты для большого режима
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(self.scrollViewBoundsChanged),
                                              name: NSView.boundsDidChangeNotification,
                                              object: scrollView.contentView)
    }

    func update(stage: PipelineStage) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.titleLabel.stringValue = stage.title
            self.detailLabel.stringValue = stage.detail
            self.scrollView.isHidden = true
            self.largeTextView.string = ""
            
            // Показываем кнопку retry только при ошибках
            let isError = stage.title.contains("Ошибка")
            self.retryButton.isHidden = !isError

            // Показываем кнопку Отмена в стадиях: запись, отправка, ожидание
            let showCancel: Bool
            switch stage {
            case .recording, .uploading, .waitingForTranscription:
                showCancel = true
            default:
                showCancel = false
            }
            self.cancelButton.isHidden = !showCancel
            
            // Увеличиваем высоту панели если есть кнопка retry
            let newHeight: CGFloat = (isError || showCancel) ? 140 : 110
            let newSize = NSSize(width: self.compactWidth, height: newHeight)
            let newFrame = NSRect(origin: self.panel.frame.origin, size: newSize)
            self.panel.setFrame(newFrame, display: true)
            
            self.reposition()
            self.showPanel()

            if let delay = stage.autoHideDelay {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.hidePanel()
                }
                self.hideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }

    func showLargeScrollable(text: String) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.titleLabel.stringValue = "Ответ"
            self.detailLabel.stringValue = ""
            self.updateTextContainerSize()
            self.setMarkdownText(text)
            self.scrollView.isHidden = false

            // Размер панели: шире и почти на всю высоту экрана
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let width = max(600, frame.width * 0.6)
                let height = max(400, frame.height * 0.9)
                let newSize = NSSize(width: width, height: height)
                var newFrame = NSRect(origin: .zero, size: newSize)
                newFrame.origin.x = frame.midX - width/2
                newFrame.origin.y = frame.midY - height/2
                self.panel.setFrame(newFrame, display: true)
            }

            self.repositionForLarge()
            self.updateTextContainerSize()
            self.showPanel()
        }
    }

    // Показ простого уведомления с заголовком/подзаголовком и опциональным авто-скрытием
    func showNotice(title: String, detail: String, autoHide: TimeInterval? = 2.0) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.titleLabel.stringValue = title
            self.detailLabel.stringValue = detail
            self.scrollView.isHidden = true
            self.largeTextView.string = ""

            // Уведомление — компактная высота и без кнопки retry
            self.retryButton.isHidden = true
            let newHeight: CGFloat = 110
            let newSize = NSSize(width: self.compactWidth, height: newHeight)
            let newFrame = NSRect(origin: self.panel.frame.origin, size: newSize)
            self.panel.setFrame(newFrame, display: true)

            self.reposition()
            self.showPanel()

            if let delay = autoHide {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.hidePanel()
                }
                self.hideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }

    private func repositionForLarge() {
        // Центрируем большое окно
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        var panelFrame = panel.frame
        panelFrame.origin.x = frame.midX - panelFrame.width/2
        panelFrame.origin.y = frame.midY - panelFrame.height/2
        panel.setFrame(panelFrame, display: true)
    }

    private func updateTextContainerSize() {
        // Подгоняем ширину контейнера под видимую область, чтобы строки переносились
        let contentWidth = self.scrollView.contentSize.width
        let insets = self.largeTextView.textContainerInset
        let targetWidth = max(0, contentWidth - (insets.width * 2))
        if let container = self.largeTextView.textContainer {
            container.containerSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
            container.widthTracksTextView = true
        }
        // Подгоняем саму ширину текстового вида под видимую область
        var frame = self.largeTextView.frame
        if abs(frame.size.width - contentWidth) > 0.5 {
            frame.size.width = contentWidth
            self.largeTextView.frame = frame
        }
    }

    private func setMarkdownText(_ text: String) {
        // Рендерим Markdown. Если не удаётся — показываем как обычный текст
        if #available(macOS 12.0, *) {
            if let attributed = try? AttributedString(markdown: text) {
                let nsAttr = NSAttributedString(attributed)
                self.largeTextView.textStorage?.setAttributedString(nsAttr)
                return
            }
        }
        // Фоллбек
        self.largeTextView.string = text
    }

    @objc private func scrollViewBoundsChanged() {
        updateTextContainerSize()
    }

    func revealTemporarily() {
        update(stage: .idle)
        let workItem = DispatchWorkItem { [weak self] in
            self?.hidePanel()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let frame = screen.visibleFrame
        var panelFrame = panel.frame
        panelFrame.origin.x = frame.maxX - panelFrame.width - margin
        panelFrame.origin.y = frame.maxY - panelFrame.height - margin
        panel.setFrame(panelFrame, display: true)
    }

    private func showPanel() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }

    private func hidePanel() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            self.panel.orderOut(nil)
        }
    }
    
    @objc private func closeButtonClicked() {
        hideWorkItem?.cancel()
        hidePanel()
    }
    
    @objc private func retryButtonClicked() {
        onRetry?()
        hidePanel()
    }

    @objc private func cancelButtonClicked() {
        onCancel?()
        hidePanel()
    }
    
    func hideImmediately() {
        hideWorkItem?.cancel()
        hidePanel()
    }
}

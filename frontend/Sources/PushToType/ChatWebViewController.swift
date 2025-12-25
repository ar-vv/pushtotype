import AppKit
import WebKit

@MainActor
final class ChatWebViewController: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView

    override init() {
        let initialSize = NSSize(width: 800, height: 600)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "Ответ"
        window.isReleasedWhenClosed = false
        // Убеждаемся, что окно следует системной теме
        window.appearance = NSAppearance.current
        window.contentView?.wantsLayer = true

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: initialSize))
        window.contentView = contentView
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        super.init()
        webView.navigationDelegate = self
        loadSkeleton()
    }

    private func loadSkeleton() {
        // Встраиваем минимальный HTML + CSS, похожий на ChatGPT, и скрипты marked.js + highlight.js
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset=\"utf-8\">
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
          <title>Ответ</title>
          <link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css\"> 
          <style>
            :root {
              color-scheme: light dark;
            }
            html, body { height: 100%; margin: 0; padding: 0; }
            body {
              font: 15px/1.6 -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, Inter, Helvetica, Arial, \"Apple Color Emoji\", \"Segoe UI Emoji\";
              background: rgb(255, 255, 255);
              color: rgb(28, 28, 30);
            }
            @media (prefers-color-scheme: dark) {
              body { 
                background: rgb(28, 28, 30);
                color: rgb(229, 229, 234);
              }
            }
            .container { max-width: 900px; margin: 0 auto; padding: 16px 24px 20px; }
            .question-section {
              margin-bottom: 20px;
              padding-bottom: 16px;
              border-bottom: 2px solid rgba(60,60,67,0.2);
            }
            .question-label {
              font-size: 0.8rem;
              font-weight: 600;
              text-transform: uppercase;
              letter-spacing: 0.5px;
              color: rgba(60,60,67,0.6);
              margin-bottom: 8px;
            }
            @media (prefers-color-scheme: dark) {
              .question-label { color: rgba(229,229,234,0.6); }
              .question-section { border-bottom-color: rgba(229,229,234,0.2); }
            }
            .question-text {
              word-wrap: break-word; overflow-wrap: anywhere; white-space: pre-wrap;
              font-size: 15px;
              line-height: 1.6;
              color: rgb(28, 28, 30);
            }
            @media (prefers-color-scheme: dark) {
              .question-text {
                color: rgb(229, 229, 234);
              }
            }
            .answer-section {
              margin-top: 16px;
            }
            .answer-label {
              font-size: 0.8rem;
              font-weight: 600;
              text-transform: uppercase;
              letter-spacing: 0.5px;
              color: rgba(60,60,67,0.6);
              margin-bottom: 8px;
            }
            @media (prefers-color-scheme: dark) {
              .answer-label { color: rgba(229,229,234,0.6); }
            }
            .loader {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              color: rgba(60,60,67,0.6);
              font-size: 14px;
            }
            @media (prefers-color-scheme: dark) {
              .loader { color: rgba(229,229,234,0.6); }
            }
            .loader-dots {
              display: inline-flex;
              gap: 4px;
            }
            .loader-dot {
              width: 6px;
              height: 6px;
              border-radius: 50%;
              background: rgba(60,60,67,0.4);
              animation: pulse 1.4s ease-in-out infinite;
            }
            @media (prefers-color-scheme: dark) {
              .loader-dot { background: rgba(229,229,234,0.4); }
            }
            .loader-dot:nth-child(2) {
              animation-delay: 0.2s;
            }
            .loader-dot:nth-child(3) {
              animation-delay: 0.4s;
            }
            @keyframes pulse {
              0%, 100% { opacity: 0.4; transform: scale(1); }
              50% { opacity: 1; transform: scale(1.2); }
            }
            .markdown { 
              word-wrap: break-word; overflow-wrap: anywhere; white-space: pre-wrap; 
            }
            .markdown h1 { font-size: 1.4rem; font-weight: 700; margin: 0.4em 0 0.2em; }
            .markdown h2 { font-size: 1.2rem; font-weight: 700; margin: 0.4em 0 0.15em; }
            .markdown h3 { font-size: 1.1rem; font-weight: 700; margin: 0.35em 0 0.1em; }
            .markdown p { margin: 0.2em 0; }
            .markdown ul, .markdown ol { padding-left: 1.2em; margin: 0.2em 0; }
            .markdown li { margin: 0.1em 0; }
            .markdown blockquote { 
              margin: 0.3em 0; padding: 0.1em 0.8em; border-left: 3px solid rgba(60,60,67,0.3);
              color: rgba(60,60,67,0.9);
            }
            @media (prefers-color-scheme: dark) {
              .markdown blockquote { 
                border-left-color: rgba(229,229,234,0.3);
                color: rgba(229,229,234,0.9);
              }
            }
            .markdown code { 
              font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", monospace; 
              background: rgba(60,60,67,0.08); padding: 2px 5px; border-radius: 6px;
              color: rgb(28, 28, 30);
            }
            @media (prefers-color-scheme: dark) {
              .markdown code { 
                background: rgba(229,229,234,0.15);
                color: rgb(229, 229, 234);
              }
            }
            .markdown pre code { background: transparent; padding: 0; }
            .markdown pre { 
              background: rgba(60,60,67,0.08); padding: 10px 12px; border-radius: 8px; overflow: auto;
              margin: 0.3em 0;
            }
            @media (prefers-color-scheme: dark) {
              .markdown pre { 
                background: rgba(229,229,234,0.15);
              }
            }
            a { color: #0b57d0; text-decoration: none; }
            @media (prefers-color-scheme: dark) {
              a { color: #8ab4f8; }
            }
            a:hover { text-decoration: underline; }
            table { border-collapse: collapse; }
            th, td { border: 1px solid rgba(60,60,67,0.2); padding: 6px 10px; }
            @media (prefers-color-scheme: dark) {
              th, td { border-color: rgba(229,229,234,0.2); }
            }
          </style>
        </head>
        <body>
          <div class=\"container\">
            <div id=\"question-section\" class=\"question-section\" style=\"display: none;\">
              <div class=\"question-label\">Ваш вопрос</div>
              <div id=\"question-text\" class=\"question-text\"></div>
            </div>
            <div id=\"answer-section\" class=\"answer-section\">
              <div class=\"answer-label\">Ответ</div>
              <div id=\"answer-content\" class=\"markdown\">
                <div class=\"loader\">
                  <span>Ожидание ответа</span>
                  <div class=\"loader-dots\">
                    <div class=\"loader-dot\"></div>
                    <div class=\"loader-dot\"></div>
                    <div class=\"loader-dot\"></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <script src=\"https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js\"></script>
          <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js\"></script>
          <script>
            marked.use({
              mangle: false,
              headerIds: false,
              gfm: true,
              breaks: true
            });
            function setQuestion(question) {
              const questionSection = document.getElementById('question-section');
              const questionText = document.getElementById('question-text');
              // Безопасное экранирование HTML
              const div = document.createElement('div');
              div.textContent = question;
              questionText.innerHTML = div.innerHTML;
              questionSection.style.display = 'block';
            }
            function setAnswer(md) {
              try {
                const html = marked.parse(md);
                const container = document.getElementById('answer-content');
                container.innerHTML = html;
                document.querySelectorAll('pre code').forEach((el) => hljs.highlightElement(el));
              } catch (e) {
                document.getElementById('answer-content').textContent = md;
              }
            }
            function setMarkdown(md) {
              setAnswer(md);
            }
            window.setQuestion = setQuestion;
            window.setAnswer = setAnswer;
            window.setMarkdown = setMarkdown;
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func showQuestion(_ question: String) {
        // Активируем приложение, чтобы окно получило фокус
        NSApp.activate(ignoringOtherApps: true)
        
        // Центрируем окно и отображаем
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            var wframe = window.frame
            wframe.origin.x = frame.midX - wframe.width/2
            wframe.origin.y = frame.midY - wframe.height/2
            window.setFrame(wframe, display: true)
        }
        window.makeKeyAndOrderFront(nil)

        // Передаем вопрос после загрузки документа
        let escaped = question
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        let js = "window.setQuestion(\"\(escaped)\");"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    func updateAnswer(_ markdown: String) {
        // Передаем markdown ответа
        let escaped = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        let js = "window.setAnswer(\"\(escaped)\");"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    func show(markdown: String) {
        // Активируем приложение, чтобы окно получило фокус
        NSApp.activate(ignoringOtherApps: true)
        
        // Центрируем окно и отображаем
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            var wframe = window.frame
            wframe.origin.x = frame.midX - wframe.width/2
            wframe.origin.y = frame.midY - wframe.height/2
            window.setFrame(wframe, display: true)
        }
        window.makeKeyAndOrderFront(nil)

        // Передаем markdown после загрузки документа
        let escaped = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        let js = "window.setMarkdown(\"\(escaped)\");"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}




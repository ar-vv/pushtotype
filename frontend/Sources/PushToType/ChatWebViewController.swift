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
            html, body { height: 100%; }
            body {
              margin: 0; padding: 0; 
              font: 15px/1.6 -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, Inter, Helvetica, Arial, \"Apple Color Emoji\", \"Segoe UI Emoji\";
              background: transparent;
              color: rgb(28,28,30);
            }
            @media (prefers-color-scheme: dark) {
              body { color: rgb(229,229,234); background: transparent; }
            }
            .container { max-width: 900px; margin: 0 auto; padding: 20px 28px 40px; }
            .markdown { 
              word-wrap: break-word; overflow-wrap: anywhere; white-space: pre-wrap; 
            }
            .markdown h1 { font-size: 1.6rem; font-weight: 700; margin: 1.2em 0 0.24em; }
            .markdown h2 { font-size: 1.35rem; font-weight: 700; margin: 1.1em 0 0.20em; }
            .markdown h3 { font-size: 1.15rem; font-weight: 700; margin: 1em 0 0.16em; }
            .markdown p { margin: 0.6em 0; }
            .markdown ul, .markdown ol { padding-left: 1.35em; margin: 0.6em 0; }
            .markdown blockquote { 
              margin: 0.9em 0; padding: 0.1em 1em; border-left: 3px solid rgba(60,60,67,0.3);
              color: rgba(60,60,67,0.9);
            }
            .markdown code { 
              font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", monospace; 
              background: rgba(60,60,67,0.08); padding: 2px 5px; border-radius: 6px;
            }
            .markdown pre code { background: transparent; padding: 0; }
            .markdown pre { 
              background: rgba(60,60,67,0.08); padding: 14px 16px; border-radius: 10px; overflow: auto;
            }
            a { color: #0b57d0; text-decoration: none; }
            a:hover { text-decoration: underline; }
            table { border-collapse: collapse; }
            th, td { border: 1px solid rgba(60,60,67,0.2); padding: 6px 10px; }
          </style>
        </head>
        <body>
          <div class=\"container\"><div id=\"content\" class=\"markdown\">Загрузка…</div></div>
          <script src=\"https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js\"></script>
          <script src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js\"></script>
          <script>
            marked.use({
              mangle: false,
              headerIds: false,
              gfm: true,
              breaks: true
            });
            function setMarkdown(md) {
              try {
                const html = marked.parse(md);
                const container = document.getElementById('content');
                container.innerHTML = html;
                document.querySelectorAll('pre code').forEach((el) => hljs.highlightElement(el));
              } catch (e) {
                document.getElementById('content').textContent = md;
              }
            }
            // Поддержка передачи из native через window.webkit.messageHandlers
            window.setMarkdown = setMarkdown;
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func show(markdown: String) {
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



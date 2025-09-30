import Foundation

enum PTLog {
    private static let logURL = URL(fileURLWithPath: "/tmp/pushtotype_frontend.log")

    static func write(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logURL)
            }
        }
        #if DEBUG
        print(line)
        #endif
    }
}



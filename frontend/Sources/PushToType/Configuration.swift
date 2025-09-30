import Foundation

struct AppConfiguration: Codable {
    let backend: BackendConfiguration
    let frontend: FrontendConfiguration
}

struct BackendConfiguration: Codable {
    let host: String
    let port: Int
    let baseUrl: String
    
    enum CodingKeys: String, CodingKey {
        case host
        case port
        case baseUrl = "base_url"
    }
}

struct FrontendConfiguration: Codable {
    let pollingInterval: TimeInterval
    let timeout: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case pollingInterval = "polling_interval"
        case timeout
    }
}

final class Configuration: @unchecked Sendable {
    static let shared = Configuration()
    
    private let config: AppConfiguration
    
    private init() {
        // Ищем файл конфигурации: приоритет у ENV PUSHTOTYPE_CONFIG, затем ./config.json в корне репо.
        // Текущее расположение файла: .../pushtotype/frontend/Sources/PushToType/Configuration.swift
        // Поднимемся: PushToType -> Sources -> frontend, затем ещё на один уровень -> pushtotype
        let frontendDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // PushToType
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // frontend
        let projectRoot = frontendDir.deletingLastPathComponent() // pushtotype

        let envPath = ProcessInfo.processInfo.environment["PUSHTOTYPE_CONFIG"]
        let envURL = envPath.flatMap { URL(fileURLWithPath: $0) }
        let primaryConfigURL = projectRoot.appendingPathComponent("config.json")
        let fallbackConfigURL = frontendDir.appendingPathComponent("config.json")

        do {
            let configPathToUse: URL
            if let envURL, FileManager.default.fileExists(atPath: envURL.path) {
                configPathToUse = envURL
            } else if FileManager.default.fileExists(atPath: primaryConfigURL.path) {
                configPathToUse = primaryConfigURL
            } else {
                configPathToUse = fallbackConfigURL
            }
            let data = try Data(contentsOf: configPathToUse)
            config = try JSONDecoder().decode(AppConfiguration.self, from: data)
            PTLog.write("config path=\(configPathToUse.path) base_url=\(config.backend.baseUrl)")
        } catch {
            // Fallback к значениям по умолчанию
            print("⚠️ Не удалось загрузить конфигурацию: \(error)")
            print("📝 Используем значения по умолчанию")
            config = AppConfiguration(
                backend: BackendConfiguration(
                    host: "127.0.0.1",
                    port: 5001,
                    baseUrl: "http://127.0.0.1:5001"
                ),
                frontend: FrontendConfiguration(
                    pollingInterval: 1.5,
                    timeout: 60
                )
            )
            PTLog.write("config fallback to default http://127.0.0.1:5001")
        }
    }
    
    var backendBaseURL: URL {
        return URL(string: config.backend.baseUrl)!
    }
    
    var pollingInterval: TimeInterval {
        return config.frontend.pollingInterval
    }
    
    var timeout: TimeInterval {
        return config.frontend.timeout
    }
}

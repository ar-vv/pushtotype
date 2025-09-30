import Foundation

enum PipelineStage {
    case idle
    case recording
    case uploading
    case waitingForTranscription
    case chatResponding
    case completed
    case awaitingAccessibility
    case error(String)

    var title: String {
        switch self {
        case .idle:
            return "Ожидание"
        case .recording:
            return "Запись"
        case .uploading:
            return "Транскрибация"
        case .waitingForTranscription:
            return "Транскрибация"
        case .chatResponding:
            return "Отвечаем"
        case .completed:
            return "Сохранено в буфер"
        case .awaitingAccessibility:
            return "Нужен доступ к доступности"
        case .error:
            return "Ошибка"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Готов к записи"
        case .recording:
            return "Удерживайте Ctrl+V"
        case .uploading:
            return "отправляем аудио"
        case .waitingForTranscription:
            return "ждем текст"
        case .chatResponding:
            return "ждем ответ"
        case .completed:
            return "Текст скопирован"
        case .awaitingAccessibility:
            return "Разрешите доступ в настройках"
        case .error(let message):
            return message
        }
    }

    var autoHideDelay: TimeInterval? {
        switch self {
        case .completed:
            return 2.5
        case .error:
            return 4.0
        default:
            return nil
        }
    }
}

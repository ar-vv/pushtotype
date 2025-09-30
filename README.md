# PushToType

macOS приложение для преобразования речи в текст с помощью горячих клавиш.

## Архитектура

- **Бекенд**: Flask-сервер для обработки аудио и транскрипции
- **Фронтенд**: Swift/macOS приложение с status bar интерфейсом

## Быстрый запуск

### 1. Запуск бекенда
```bash
./run_backend.sh
```

### 2. Запуск фронтенда (в новом терминале)
```bash
./run_frontend.sh
```

## Конфигурация

Настройки находятся в файле `config.json`:

```json
{
  "backend": {
    "host": "127.0.0.1",
    "port": 5001,
    "base_url": "http://127.0.0.1:5001"
  },
  "frontend": {
    "polling_interval": 1.5,
    "timeout": 60
  }
}
```

## Использование

1. После запуска приложение появится в status bar (иконка с волной)
2. Удерживайте клавишу **пробел** для записи аудио
3. Отпустите клавишу для остановки записи и начала транскрипции
4. Текст автоматически вставится в активное поле ввода

## Требования

- macOS 13.0+
- Python 3.8+
- Swift 6.0+
- Доступ к микрофону
- Разрешения Accessibility для автоматической вставки текста

## API Endpoints

### POST /api/audio
Загрузка аудиофайла для транскрипции.

### GET /api/transcription/{job_id}
Получение результата транскрипции.

## Структура проекта

```
├── backend/
│   ├── server.py          # Flask сервер
│   ├── requirements.txt   # Python зависимости
│   └── venv/             # Виртуальное окружение
├── frontend/
│   ├── Package.swift     # Swift Package Manager
│   └── Sources/PushToType/
│       ├── main.swift
│       ├── AppDelegate.swift
│       ├── BackendClient.swift
│       ├── Configuration.swift
│       └── ...
├── config.json           # Конфигурация
├── run_backend.sh        # Скрипт запуска бекенда
└── run_frontend.sh       # Скрипт запуска фронтенда
```


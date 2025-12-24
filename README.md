# PushToType

**Professional Speech-to-Text Solution for macOS | Real-Time Voice Transcription | AI-Powered Audio-to-Text Converter**

---

## 🎯 What PushToType Can Do

**PushToType** is a powerful, open-source **speech-to-text application** and **voice transcription tool** designed specifically for macOS. Transform your voice into text instantly with professional-grade accuracy using cutting-edge AI technology.

### Core Features:

✅ **Real-Time Voice Transcription** - Convert speech to text in real-time with a simple hotkey press  
✅ **Automatic Text Insertion** - Transcribed text automatically appears in any active text field  
✅ **AI-Powered Transcription** - Powered by OpenAI Whisper and AssemblyAI for industry-leading accuracy  
✅ **Smart Text Formatting** - AI automatically formats and improves your transcriptions  
✅ **Intelligent Summarization** - Get concise summaries of your voice recordings  
✅ **Multi-Language Support** - Automatic language detection for global users  
✅ **Telegram Bot Integration** - Transcribe voice messages directly in Telegram  
✅ **Audio File Transcription** - Upload and transcribe any audio file format  
✅ **ChatGPT Integration** - Ask questions and get AI-powered responses via voice  
✅ **Hotkey-Controlled** - One-key operation for seamless workflow integration  
✅ **Background Operation** - Runs silently in your menu bar, always ready  

### Use Cases:

- **Voice Dictation** - Replace typing with voice for faster content creation
- **Meeting Notes** - Transcribe meetings, interviews, and conversations
- **Content Creation** - Convert voice memos into written content
- **Accessibility** - Voice-to-text solution for users with typing difficulties
- **Multilingual Communication** - Transcribe in multiple languages automatically
- **Telegram Voice Messages** - Convert Telegram voice messages to text
- **Audio File Processing** - Transcribe podcasts, recordings, and audio files

---

## 🎯 Что может делать PushToType

**PushToType** — это мощное приложение с открытым исходным кодом для **преобразования речи в текст** и **транскрипции голоса**, разработанное специально для macOS. Превращайте свой голос в текст мгновенно с профессиональной точностью, используя передовые технологии искусственного интеллекта.

### Основные возможности:

✅ **Транскрипция в реальном времени** - Преобразуйте речь в текст в реальном времени одним нажатием горячей клавиши  
✅ **Автоматическая вставка текста** - Расшифрованный текст автоматически появляется в любом активном поле ввода  
✅ **Транскрипция на базе ИИ** - Использует OpenAI Whisper и AssemblyAI для максимальной точности  
✅ **Умное форматирование текста** - ИИ автоматически форматирует и улучшает ваши транскрипции  
✅ **Интеллектуальное суммирование** - Получайте краткие версии ваших голосовых записей  
✅ **Поддержка нескольких языков** - Автоматическое определение языка для пользователей по всему миру  
✅ **Интеграция с Telegram** - Транскрибируйте голосовые сообщения прямо в Telegram  
✅ **Транскрипция аудио файлов** - Загружайте и транскрибируйте файлы любого аудио формата  
✅ **Интеграция с ChatGPT** - Задавайте вопросы и получайте ответы от ИИ через голос  
✅ **Управление горячими клавишами** - Работа одной клавишей для бесшовной интеграции в рабочий процесс  
✅ **Работа в фоне** - Работает незаметно в строке меню, всегда готов к использованию  

### Области применения:

- **Голосовой ввод** - Замените печать голосом для более быстрого создания контента
- **Заметки на встречах** - Транскрибируйте встречи, интервью и разговоры
- **Создание контента** - Превращайте голосовые заметки в письменный контент
- **Доступность** - Решение для преобразования голоса в текст для пользователей с трудностями при печати
- **Многоязычное общение** - Транскрибируйте на нескольких языках автоматически
- **Голосовые сообщения Telegram** - Преобразуйте голосовые сообщения Telegram в текст
- **Обработка аудио файлов** - Транскрибируйте подкасты, записи и аудио файлы

---

## Architecture

- **Backend**: Flask server for audio processing and transcription
- **Frontend**: Swift/macOS application with status bar interface

## Quick Start

### 1. Start Backend
```bash
./run_backend.sh
```

### 2. Start Frontend (in a new terminal)
```bash
./run_frontend.sh
```

## Configuration

Settings are located in `config.json`:

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

## Usage

1. After launching, the application will appear in the status bar (wave icon)
2. Hold the **Space** key to record audio
3. Release the key to stop recording and start transcription
4. Text will automatically be inserted into the active input field

## Requirements

- macOS 13.0+
- Python 3.8+
- Swift 6.0+
- Microphone access
- Accessibility permissions for automatic text insertion

## API Endpoints

### POST /api/audio
Upload audio file for transcription.

### GET /api/transcription/{job_id}
Get transcription result.

## Project Structure

```
├── backend/
│   ├── server.py          # Flask server
│   ├── requirements.txt   # Python dependencies
│   └── venv/             # Virtual environment
├── frontend/
│   ├── Package.swift     # Swift Package Manager
│   └── Sources/PushToType/
│       ├── main.swift
│       ├── AppDelegate.swift
│       ├── BackendClient.swift
│       ├── Configuration.swift
│       └── ...
├── config.json           # Configuration
├── run_backend.sh        # Backend startup script
└── run_frontend.sh       # Frontend startup script
```

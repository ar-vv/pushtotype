# PushToType Production Deployment Guide

## Production Deployment for PushToType

Below are instructions for deploying on a server (Ubuntu) and connecting the frontend.

### 1) Project Placement on Server

- Folder: `/opt/pushtotype`
- Files:
  - `backend/server.py`, `backend/requirements.txt`
  - `config.json` (production config on server)
  - `data/` directory for audio and results

### 2) Backend Dependencies

```bash
cd /opt/pushtotype/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3) Configuration

- Use `config.json` in the root `/opt/pushtotype`.
- For production environment, you can use the example `config.prod.json` from the repository. Replace `YOUR_*_API_KEY` with real keys and copy as `config.json` to the server:

```bash
scp -i ~/.ssh/your_key config.prod.json root@<SERVER_IP>:/opt/pushtotype/config.json
```

Key fields:
- `backend.host` = `0.0.0.0`
- `backend.port` = `5001`
- `backend.base_url` = `http://<SERVER_IP>:5001`

### 4) Backend Startup

One-time startup (foreground):
```bash
cd /opt/pushtotype/backend
source venv/bin/activate
PORT=5001 python server.py
```

Background startup (simple):
```bash
cd /opt/pushtotype/backend
source venv/bin/activate
nohup env PORT=5001 python server.py > /var/log/pushtotype/server.log 2>&1 & echo $! > /run/pushtotype/pid
```

Port check:
```bash
ss -ltn '( sport = :5001 )'
```

Stop background process:
```bash
kill $(cat /run/pushtotype/pid)
```

### 5) Nginx (Optional)

You can proxy through `nginx` on ports `80/443`.

```
location /api/ {
    proxy_pass http://127.0.0.1:5001;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

### 6) API Testing

```bash
curl -F 'audio=@test_audio.m4a' http://<SERVER_IP>:5001/api/audio
curl http://<SERVER_IP>:5001/api/transcription/<recording_id>
```

### 7) Frontend Connection (macOS app)

- Place `config.json` in the root of the macOS application project so that `Configuration.swift` reads `backend.base_url` in the format `http://<SERVER_IP>:5001`.
- Build and run the application; it will send audio to the server and poll `/api/transcription/<id>`.

---

# Руководство по развертыванию PushToType в продакшене

## Продовый запуск PushToType

Ниже инструкция для развертывания на сервере (Ubuntu) и подключения фронтенда.

### 1) Размещение проекта на сервере

- Папка: `/opt/pushtotype`
- Файлы:
  - `backend/server.py`, `backend/requirements.txt`
  - `config.json` (рабочий конфиг на сервере)
  - Директория `data/` для аудио и результатов

### 2) Зависимости бэкенда

```bash
cd /opt/pushtotype/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3) Конфигурация

- Используется `config.json` в корне `/opt/pushtotype`.
- Для прод окружения можно использовать пример `config.prod.json` из репозитория. Замените `YOUR_*_API_KEY` на реальные ключи и скопируйте как `config.json` на сервер:

```bash
scp -i ~/.ssh/your_key config.prod.json root@<SERVER_IP>:/opt/pushtotype/config.json
```

Ключевые поля:
- `backend.host` = `0.0.0.0`
- `backend.port` = `5001`
- `backend.base_url` = `http://<SERVER_IP>:5001`

### 4) Запуск бэкенда

Разовый запуск (foreground):
```bash
cd /opt/pushtotype/backend
source venv/bin/activate
PORT=5001 python server.py
```

Фоновый запуск (simple):
```bash
cd /opt/pushtotype/backend
source venv/bin/activate
nohup env PORT=5001 python server.py > /var/log/pushtotype/server.log 2>&1 & echo $! > /run/pushtotype/pid
```

Проверка порта:
```bash
ss -ltn '( sport = :5001 )'
```

Остановка фонового процесса:
```bash
kill $(cat /run/pushtotype/pid)
```

### 5) Nginx (опционально)

Можно проксировать через `nginx` на `80/443`.

```
location /api/ {
    proxy_pass http://127.0.0.1:5001;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

### 6) Тестирование API

```bash
curl -F 'audio=@test_audio.m4a' http://<SERVER_IP>:5001/api/audio
curl http://<SERVER_IP>:5001/api/transcription/<recording_id>
```

### 7) Подключение фронтенда (macOS app)

- Поместите `config.json` в корень проекта macOS-приложения, чтобы `Configuration.swift` прочитал `backend.base_url` вида `http://<SERVER_IP>:5001`.
- Соберите и запустите приложение; оно будет отправлять аудио на сервер и опрашивать `/api/transcription/<id>`.

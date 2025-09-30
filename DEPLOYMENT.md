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
scp -i ~/.ssh/cursor config.prod.json root@<SERVER_IP>:/opt/pushtotype/config.json
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









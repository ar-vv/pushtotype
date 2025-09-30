import json
import os
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Dict, Optional

import assemblyai as aai
from flask import Flask, jsonify, request, send_from_directory
import requests


DATA_DIR = os.path.join(os.path.dirname(__file__), "data")

# ----------------------
# Конфигурация бэкенда
# ----------------------

def _load_backend_config() -> dict:
    """Загружает конфиг с диска с поддержкой стандартных путей и ENV-перекрытий.

    Порядок поиска файла:
      1) ENV PUSHTOTYPE_CONFIG (если задан и файл существует)
      2) ./config.json в корне проекта (../config.json относительно server.py)
      3) /etc/pushtotype/config.json

    ENV-перекрытия отдельных полей (если заданы):
      - BACKEND_HOST, BACKEND_PORT, BACKEND_BASE_URL
      - ASSEMBLYAI_API_KEY, OPENAI_API_KEY, OPENAI_MODEL
    """

    # Кандидаты путей
    candidates = []
    env_cfg = os.environ.get("PUSHTOTYPE_CONFIG")
    if env_cfg:
        candidates.append(env_cfg)
    # проектный config рядом с репозиторием
    candidates.append(os.path.join(os.path.dirname(__file__), "..", "config.json"))
    # системный путь
    candidates.append("/etc/pushtotype/config.json")

    config_data: dict = {}
    for path in candidates:
        try:
            if path and os.path.isfile(path):
                with open(path, "r", encoding="utf-8") as f:
                    config_data = json.load(f)
                break
        except Exception:
            # Переходим к следующему кандидату
            pass

    # Дефолты, если файл не найден или неполный
    backend_cfg = (config_data.get("backend") or {})
    frontend_cfg = (config_data.get("frontend") or {})
    api_keys_cfg = (config_data.get("api_keys") or {})
    openai_cfg = (config_data.get("openai") or {})

    host = os.environ.get("BACKEND_HOST") or backend_cfg.get("host") or "0.0.0.0"
    port_val = os.environ.get("BACKEND_PORT") or backend_cfg.get("port") or 5001
    try:
        port = int(port_val)
    except (TypeError, ValueError):
        port = 5001

    base_url = os.environ.get("BACKEND_BASE_URL") or backend_cfg.get("base_url")
    if not base_url:
        # Пытаемся собрать base_url из host/port, предполагая http
        base_url = f"http://{host}:{port}"

    assemblyai_key = os.environ.get("ASSEMBLYAI_API_KEY") or api_keys_cfg.get("assemblyai", "")
    openai_key = os.environ.get("OPENAI_API_KEY") or api_keys_cfg.get("openai", "")
    openai_model = os.environ.get("OPENAI_MODEL") or (openai_cfg.get("model") or "gpt-4o-mini")

    return {
        "backend": {
            "host": host,
            "port": port,
            "base_url": base_url,
        },
        "frontend": {
            "polling_interval": frontend_cfg.get("polling_interval", 1.5),
            "timeout": frontend_cfg.get("timeout", 180),
        },
        "api_keys": {
            "assemblyai": assemblyai_key,
            "openai": openai_key,
        },
        "openai": {
            "model": openai_model,
        },
    }


config = _load_backend_config()

# Инициализация зависимостей по конфигу/ENV
os.makedirs(DATA_DIR, exist_ok=True)

aai.settings.api_key = config["api_keys"].get("assemblyai", "")
OPENAI_API_KEY = config["api_keys"].get("openai", "")
OPENAI_MODEL = (config.get("openai") or {}).get("model", "gpt-4o-mini")

app = Flask(__name__)


@dataclass
class TranscriptionJob:
    audio_path: str
    transcription_path: str
    status: str = "processing"
    transcription_text: Optional[str] = None


jobs: Dict[str, TranscriptionJob] = {}


@app.get("/files/<path:filename>")
def serve_file(filename: str):
    # Публичная раздача аудиофайла для AssemblyAI по прямому URL
    return send_from_directory(DATA_DIR, filename, mimetype="audio/m4a", as_attachment=False, conditional=True)


def transcribe_with_assemblyai(job_id: str) -> None:
    """Транскрибация через AssemblyAI по публичному URL (audio_url)."""
    job = jobs[job_id]

    try:
        # Собираем публичный URL для только что сохранённого файла
        base_url = (config["backend"]["base_url"]).rstrip("/")
        audio_url = f"{base_url}/files/{os.path.basename(job.audio_path)}"

        headers = {
            "authorization": aai.settings.api_key,
            "content-type": "application/json",
        }
        payload = {
            "audio_url": audio_url,
            "punctuate": True,
            "format_text": True,
            "language_detection": True,
            # Ускоряем обработку
            "dual_channel": False,
            "disfluencies": False,
            "sentiment_analysis": False,
            "auto_highlights": False,
            "entity_detection": False,
            "iab_categories": False,
            "content_safety": False,
        }

        # Создаём задачу транскрибации
        create = requests.post("https://api.assemblyai.com/v2/transcript", headers=headers, json=payload, timeout=30)
        if create.status_code >= 300:
            job.transcription_text = f"Create transcript failed: {create.status_code} {create.text}"
            job.status = "error"
            with open(job.transcription_path, "w", encoding="utf-8") as handle:
                handle.write(job.transcription_text)
            return

        tid = (create.json() or {}).get("id")
        if not tid:
            job.transcription_text = f"Create transcript invalid response: {create.text}"
            job.status = "error"
            with open(job.transcription_path, "w", encoding="utf-8") as handle:
                handle.write(job.transcription_text)
            return

        # Поллим статус
        started = time.time()
        while True:
            time.sleep(2)
            poll = requests.get(f"https://api.assemblyai.com/v2/transcript/{tid}", headers=headers, timeout=30)
            if poll.status_code >= 300:
                job.transcription_text = f"Poll failed: {poll.status_code} {poll.text}"
                job.status = "error"
                break

            data = poll.json() or {}
            st = (data.get("status") or "").lower()
            if st == "completed":
                job.transcription_text = data.get("text") or "Транскрипция пуста"
                job.status = "ready"
                break
            if st == "error":
                job.transcription_text = data.get("error") or "Ошибка транскрибации"
                job.status = "error"
                break
            if time.time() - started > 600:
                job.transcription_text = "Таймаут транскрибации"
                job.status = "error"
                break

        # Сохраняем результат в файл
        with open(job.transcription_path, "w", encoding="utf-8") as handle:
            handle.write(job.transcription_text or "")

    except Exception as e:
        job.transcription_text = f"Ошибка: {str(e)}"
        job.status = "error"
        with open(job.transcription_path, "w", encoding="utf-8") as handle:
            handle.write(job.transcription_text)


def transcribe_with_whisper_openai(job_id: str) -> bool:
    """Основная транскрибация через OpenAI Whisper API. Возвращает True при успехе."""
    if not OPENAI_API_KEY:
        return False

    job = jobs[job_id]
    try:
        with open(job.audio_path, "rb") as f:
            resp = requests.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                files={"file": f},
                data={"model": "whisper-1"},  # автоопределение языка по умолчанию
                timeout=60,
            )
        if resp.status_code == 200:
            data = resp.json() or {}
            text = data.get("text") or ""
            job.transcription_text = text if text else "Транскрипция пуста"
            job.status = "ready"
            with open(job.transcription_path, "w", encoding="utf-8") as handle:
                handle.write(job.transcription_text)
            return True
        else:
            # Логируем и даём шанс резерву
            print(f"[Whisper] {resp.status_code}: {resp.text}")
            return False
    except Exception as e:
        print(f"[Whisper] Ошибка: {e}")
        return False


def call_openai_chat(question: str) -> str:
    if not OPENAI_API_KEY:
        return "OpenAI API key отсутствует"
    try:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": OPENAI_MODEL,
            "messages": [
                {"role": "system", "content": "Ты лаконично и понятно отвечаешь на вопросы пользователя."},
                {"role": "user", "content": question},
            ],
            "temperature": 0.2,
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=60)
        if resp.status_code >= 300:
            return f"Chat error {resp.status_code}: {resp.text}"
        data = resp.json() or {}
        answer = (((data.get("choices") or [{}])[0]).get("message") or {}).get("content") or ""
        return answer.strip() or "Пустой ответ"
    except Exception as e:
        return f"Chat exception: {e}"


# (Веб-поиск не используется; функция удалена по согласованию)


@app.post("/api/audio")
def receive_audio():
    if "audio" not in request.files:
        return jsonify({"error": "Missing audio"}), 400

    audio_file = request.files["audio"]
    if audio_file.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    job_id = str(uuid.uuid4())
    audio_path = os.path.join(DATA_DIR, f"{job_id}.m4a")
    transcription_path = os.path.join(DATA_DIR, f"{job_id}.txt")

    audio_file.save(audio_path)

    jobs[job_id] = TranscriptionJob(
        audio_path=audio_path,
        transcription_path=transcription_path,
    )

    def _worker():
        ok = transcribe_with_whisper_openai(job_id)
        if not ok:
            transcribe_with_assemblyai(job_id)

    thread = threading.Thread(target=_worker, daemon=True)
    thread.start()

    return jsonify({"recording_id": job_id})


@app.get("/api/transcription/<job_id>")
def get_transcription(job_id: str):
    job = jobs.get(job_id)
    if not job:
        return jsonify({"error": "Unknown job"}), 404

    if job.status == "error":
        return jsonify({"status": job.status, "error": job.transcription_text}), 200
    if job.status != "ready":
        return jsonify({"status": job.status})

    transcription = job.transcription_text or ""

    # Cleanup audio once transcription is retrieved
    if os.path.exists(job.audio_path):
        try:
            os.remove(job.audio_path)
        except OSError:
            pass

    response = jsonify({
        "status": job.status,
        "transcription": transcription,
    })

    # Remove job from store to avoid repeated cleanup
    jobs.pop(job_id, None)

    return response


@app.post("/api/chat")
def chat_endpoint():
    try:
        payload = request.get_json(force=True) or {}
        question = (payload.get("question") or "").strip()
        if not question:
            return jsonify({"error": "question required"}), 400
        answer = call_openai_chat(question)
        return jsonify({"answer": answer})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    # Определяем host/port: приоритет у переменных окружения, затем config.json, затем дефолты
    cfg_backend = (config.get("backend") or {})
    host = os.environ.get("HOST") or cfg_backend.get("host") or "0.0.0.0"
    try:
        port = int(os.environ.get("PORT") or cfg_backend.get("port") or 5001)
    except (TypeError, ValueError):
        port = 5001
    app.run(host=host, debug=False, port=port)

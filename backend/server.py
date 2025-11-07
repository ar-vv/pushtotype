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
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config.json")

os.makedirs(DATA_DIR, exist_ok=True)

# Load config and initialize AssemblyAI
with open(CONFIG_PATH, "r", encoding="utf-8") as f:
    config = json.load(f)

aai.settings.api_key = config["api_keys"]["assemblyai"]
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


def start_telegram_bot():
    """Запускает телеграм бота в отдельном потоке"""
    try:
        # Небольшая задержка, чтобы Flask успел запуститься
        time.sleep(2)
        print("🔄 Инициализация Telegram бота...", flush=True)
        from telegram_bot import run_bot
        print("✅ Модуль telegram_bot загружен, запускаю бота...", flush=True)
        run_bot()
    except Exception as e:
        print(f"❌ Ошибка запуска Telegram бота: {e}", flush=True)
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    # Запускаем Telegram бота в отдельном потоке
    telegram_bot_thread = threading.Thread(target=start_telegram_bot, daemon=True)
    telegram_bot_thread.start()
    
    # Используем порт из конфига или ENV
    port = int(os.environ.get("PORT", config.get("backend", {}).get("port", 5000)))
    host = config.get("backend", {}).get("host", "0.0.0.0")
    print(f"🚀 Запуск Flask сервера на {host}:{port}")
    app.run(host=host, debug=False, port=port)

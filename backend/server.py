import json
import os
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Dict, Optional

# import assemblyai as aai
from flask import Flask, jsonify, request, send_from_directory
import requests


DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config.json")

os.makedirs(DATA_DIR, exist_ok=True)

# Load config and initialize AssemblyAI
with open(CONFIG_PATH, "r", encoding="utf-8") as f:
    config = json.load(f)

# aai.settings.api_key = config["api_keys"]["assemblyai"]
OPENAI_API_KEY = config["api_keys"].get("openai", "")
OPENAI_MODEL = (config.get("openai") or {}).get("model", "gpt-4o-mini")
USE_WEB_SEARCH = (config.get("openai") or {}).get("use_web_search", False)

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
    # Публичная раздача аудиофайла для AssemblyAI по прямому URL (закомментировано, не используется)
    return send_from_directory(DATA_DIR, filename, mimetype="audio/m4a", as_attachment=False, conditional=True)


# def transcribe_with_assemblyai(job_id: str) -> None:
#     """Транскрибация через AssemblyAI по публичному URL (audio_url)."""
#     job = jobs[job_id]
#
#     try:
#         # Собираем публичный URL для только что сохранённого файла
#         base_url = (config["backend"]["base_url"]).rstrip("/")
#         audio_url = f"{base_url}/files/{os.path.basename(job.audio_path)}"
#
#         headers = {
#             "authorization": aai.settings.api_key,
#             "content-type": "application/json",
#         }
#         payload = {
#             "audio_url": audio_url,
#             "punctuate": True,
#             "format_text": True,
#             "language_detection": True,
#             # Ускоряем обработку
#             "dual_channel": False,
#             "disfluencies": False,
#             "sentiment_analysis": False,
#             "auto_highlights": False,
#             "entity_detection": False,
#             "iab_categories": False,
#             "content_safety": False,
#         }
#
#         # Создаём задачу транскрибации
#         create = requests.post("https://api.assemblyai.com/v2/transcript", headers=headers, json=payload, timeout=30)
#         if create.status_code >= 300:
#             job.transcription_text = f"Create transcript failed: {create.status_code} {create.text}"
#             job.status = "error"
#             with open(job.transcription_path, "w", encoding="utf-8") as handle:
#                 handle.write(job.transcription_text)
#             return
#
#         tid = (create.json() or {}).get("id")
#         if not tid:
#             job.transcription_text = f"Create transcript invalid response: {create.text}"
#             job.status = "error"
#             with open(job.transcription_path, "w", encoding="utf-8") as handle:
#                 handle.write(job.transcription_text)
#             return
#
#         # Поллим статус
#         started = time.time()
#         while True:
#             time.sleep(2)
#             poll = requests.get(f"https://api.assemblyai.com/v2/transcript/{tid}", headers=headers, timeout=30)
#             if poll.status_code >= 300:
#                 job.transcription_text = f"Poll failed: {poll.status_code} {poll.text}"
#                 job.status = "error"
#                 break
#
#             data = poll.json() or {}
#             st = (data.get("status") or "").lower()
#             if st == "completed":
#                 job.transcription_text = data.get("text") or "Транскрипция пуста"
#                 job.status = "ready"
#                 break
#             if st == "error":
#                 job.transcription_text = data.get("error") or "Ошибка транскрибации"
#                 job.status = "error"
#                 break
#             if time.time() - started > 600:
#                 job.transcription_text = "Таймаут транскрибации"
#                 job.status = "error"
#                 break
#
#         # Сохраняем результат в файл
#         with open(job.transcription_path, "w", encoding="utf-8") as handle:
#             handle.write(job.transcription_text or "")
#
#     except Exception as e:
#         job.transcription_text = f"Ошибка: {str(e)}"
#         job.status = "error"
#         with open(job.transcription_path, "w", encoding="utf-8") as handle:
#             handle.write(job.transcription_text)


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
    """Вызывает OpenAI Responses API для получения ответа на вопрос."""
    import traceback
    import json as json_module
    
    if not OPENAI_API_KEY:
        print("[Responses API] ❌ OpenAI API key отсутствует")
        return "OpenAI API key отсутствует"
    
    url = "https://api.openai.com/v1/responses"
    
    try:
        # Пробуем сначала с messages (как в Chat Completions)
        # Responses API может использовать messages вместо input
        headers = {
            "Authorization": f"Bearer {OPENAI_API_KEY[:20]}...",  # Логируем только начало ключа
            "Content-Type": "application/json",
        }
        
        # Responses API использует input вместо messages
        payload = {
            "model": OPENAI_MODEL,
            "input": [
                {"role": "system", "content": "Ты лаконично и понятно отвечаешь на вопросы пользователя."},
                {"role": "user", "content": question},
            ],
            "temperature": 0.2,
        }
        
        # Добавляем веб-поиск если включен в конфиге
        if USE_WEB_SEARCH:
            payload["tools"] = [
                {
                    "type": "web_search"
                }
            ]
        
        print(f"[Responses API] 📤 Отправляю запрос:")
        print(f"  URL: {url}")
        print(f"  Модель: {OPENAI_MODEL}")
        print(f"  Web search: {USE_WEB_SEARCH}")
        print(f"  Вопрос: {question[:100]}..." if len(question) > 100 else f"  Вопрос: {question}")
        # Логируем payload без чувствительных данных
        safe_payload = {k: v for k, v in payload.items()}
        print(f"  Payload (без ключа): {json_module.dumps(safe_payload, ensure_ascii=False, indent=2)}")
        
        # Восстанавливаем полный ключ для запроса
        headers["Authorization"] = f"Bearer {OPENAI_API_KEY}"
        
        resp = requests.post(url, headers=headers, json=payload, timeout=60)
        
        print(f"[Responses API] 📥 Получен ответ:")
        print(f"  Статус: {resp.status_code}")
        print(f"  Headers: {dict(resp.headers)}")
        
        if resp.status_code >= 300:
            error_text = resp.text
            print(f"[Responses API] ❌ Ошибка HTTP {resp.status_code}:")
            print(f"  Полный ответ: {error_text[:1000]}")
            
            # Пробуем распарсить JSON ошибки
            try:
                error_json = resp.json()
                print(f"  JSON ошибки: {json_module.dumps(error_json, ensure_ascii=False, indent=2)}")
                error_message = error_json.get("error", {}).get("message", error_text)
                return f"Chat error {resp.status_code}: {error_message}"
            except:
                return f"Chat error {resp.status_code}: {error_text[:500]}"
        
        # Парсим успешный ответ
        try:
            data = resp.json()
        except Exception as json_error:
            print(f"[Responses API] ❌ Ошибка парсинга JSON: {json_error}")
            print(f"  Сырой ответ: {resp.text[:1000]}")
            return f"Ошибка парсинга ответа: {json_error}"
        
        print(f"[Responses API] ✅ Успешный ответ получен:")
        print(f"  Ключи в ответе: {list(data.keys())}")
        print(f"  Полный ответ (первые 2000 символов): {json_module.dumps(data, ensure_ascii=False, indent=2)[:2000]}")
        
        # Парсинг ответа из Responses API
        # Responses API возвращает структуру: output[] -> ищем message -> content[0].text
        # При использовании веб-поиска в output может быть несколько элементов:
        # 1. web_search_call - вызов веб-поиска
        # 2. message - финальный ответ с результатами
        answer = ""
        
        # Вариант 1: структура Responses API (output -> ищем message -> content -> text)
        if "output" in data and isinstance(data.get("output"), list) and len(data["output"]) > 0:
            print(f"[Responses API] 🔍 Найдена структура 'output' (Responses API)")
            print(f"  Количество элементов в output: {len(data['output'])}")
            
            # Ищем элемент типа "message" в массиве output
            message_item = None
            for item in data["output"]:
                if isinstance(item, dict) and item.get("type") == "message":
                    message_item = item
                    break
            
            # Если не нашли message, берем первый элемент (для обратной совместимости)
            if message_item is None:
                message_item = data["output"][0]
                print(f"  Message не найден, используем первый элемент")
            
            print(f"  Output item keys: {list(message_item.keys())}")
            print(f"  Output item type: {message_item.get('type', 'unknown')}")
            
            if "content" in message_item and isinstance(message_item.get("content"), list) and len(message_item["content"]) > 0:
                content_item = message_item["content"][0]
                print(f"  Content item keys: {list(content_item.keys())}")
                
                if "text" in content_item:
                    answer = content_item.get("text", "")
                    print(f"  Извлечен текст из message.content[0].text")
                elif "content" in content_item:
                    answer = content_item.get("content", "")
            elif "text" in message_item:
                answer = message_item.get("text", "")
        
        # Вариант 2: структура как в Chat Completions (choices -> message -> content)
        elif "choices" in data and isinstance(data.get("choices"), list) and len(data["choices"]) > 0:
            print(f"[Responses API] 🔍 Найдена структура 'choices' (Chat Completions)")
            choice = data["choices"][0]
            print(f"  Choice keys: {list(choice.keys())}")
            
            if "message" in choice:
                message = choice["message"]
                print(f"  Message keys: {list(message.keys())}")
                answer = message.get("content", "")
                if not answer and "text" in message:
                    answer = message.get("text", "")
            elif "content" in choice:
                answer = choice.get("content", "")
            elif "text" in choice:
                answer = choice.get("text", "")
        
        # Вариант 3: прямая структура response
        elif "response" in data:
            print(f"[Responses API] 🔍 Найдена структура 'response'")
            response_data = data.get("response")
            if isinstance(response_data, dict):
                answer = response_data.get("content", "") or response_data.get("text", "") or str(response_data)
            else:
                answer = str(response_data)
        
        # Вариант 4: прямая структура content
        elif "content" in data:
            print(f"[Responses API] 🔍 Найдена структура 'content'")
            content_data = data.get("content")
            if isinstance(content_data, dict):
                answer = content_data.get("text", "") or str(content_data)
            else:
                answer = str(content_data)
        
        # Fallback: пытаемся найти текст в любой вложенной структуре
        else:
            print(f"[Responses API] ⚠️  Неизвестная структура ответа, использую fallback")
            print(f"  Полная структура данных: {json_module.dumps(data, ensure_ascii=False, indent=2)[:3000]}")
            answer = str(data)
        
        # Убеждаемся, что answer - строка
        if not isinstance(answer, str):
            answer = str(answer)
        
        answer = answer.strip() if answer else "Пустой ответ"
        print(f"[Responses API] ✅ Извлеченный ответ ({len(answer)} символов): {answer[:200]}..." if len(answer) > 200 else f"[Responses API] ✅ Извлеченный ответ: {answer}")
        
        return answer
        
    except requests.exceptions.Timeout:
        error_msg = "Таймаут запроса к OpenAI API"
        print(f"[Responses API] ❌ {error_msg}")
        return f"Chat error: {error_msg}"
    except requests.exceptions.RequestException as e:
        error_msg = f"Ошибка сети: {e}"
        print(f"[Responses API] ❌ {error_msg}")
        import traceback
        traceback.print_exc()
        return f"Chat error: {error_msg}"
    except Exception as e:
        error_msg = f"Неожиданная ошибка: {e}"
        print(f"[Responses API] ❌ {error_msg}")
        import traceback
        traceback.print_exc()
        return f"Chat exception: {error_msg}"


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
        try:
            # Всегда используем OpenAI для транскрибации (убрали fallback на AssemblyAI для ускорения)
            ok = transcribe_with_whisper_openai(job_id)
            if not ok:
                # Если OpenAI не сработал, просто устанавливаем ошибку
                if job_id in jobs:
                    jobs[job_id].status = "error"
                    jobs[job_id].transcription_text = "Ошибка транскрибации через OpenAI"
                    try:
                        with open(jobs[job_id].transcription_path, "w", encoding="utf-8") as handle:
                            handle.write(jobs[job_id].transcription_text)
                    except:
                        pass
            # Закомментирован fallback на AssemblyAI для ускорения
            # if not ok:
            #     transcribe_with_assemblyai(job_id)
        except Exception as e:
            print(f"[Transcription Worker] Критическая ошибка в worker потоке: {e}")
            import traceback
            traceback.print_exc()
            # Устанавливаем статус ошибки для job
            if job_id in jobs:
                jobs[job_id].status = "error"
                jobs[job_id].transcription_text = f"Критическая ошибка транскрибации: {str(e)}"
                try:
                    with open(jobs[job_id].transcription_path, "w", encoding="utf-8") as handle:
                        handle.write(jobs[job_id].transcription_text)
                except:
                    pass

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
            return jsonify({"answer": "Ошибка: вопрос не указан"}), 200
        answer = call_openai_chat(question)
        # Всегда возвращаем {"answer": "..."} даже при ошибках, чтобы фронтенд мог декодировать
        return jsonify({"answer": answer})
    except Exception as e:
        # При исключении тоже возвращаем в формате answer, чтобы фронтенд мог декодировать
        return jsonify({"answer": f"Ошибка сервера: {str(e)}"}), 200


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

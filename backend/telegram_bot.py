import json
import os
import sys
import time
import uuid
from typing import Optional

import requests
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

# Настраиваем вывод без буферизации для немедленного логирования
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

# Загружаем конфиг
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config.json")
with open(CONFIG_PATH, "r", encoding="utf-8") as f:
    config = json.load(f)

TELEGRAM_BOT_TOKEN = config["api_keys"].get("telegram_bot")
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
os.makedirs(DATA_DIR, exist_ok=True)


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Обработчик команды /start"""
    await update.message.reply_text(
        "Привет! Отправь мне голосовое сообщение или аудио файл, и я сделаю транскрипцию."
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Обработчик команды /help"""
    await update.message.reply_text(
        "Просто отправь мне голосовое сообщение или аудио файл, и я верну тебе транскрипцию текста."
    )


def upload_audio_to_backend(audio_path: str) -> Optional[str]:
    """Загружает аудио файл на бэкенд через API. Возвращает recording_id или None."""
    try:
        base_url = (config["backend"]["base_url"]).rstrip("/")
        upload_url = f"{base_url}/api/audio"
        
        print(f"[Backend] Загружаю файл на бэкенд: {upload_url}")
        print(f"[Backend] Файл: {audio_path}, размер: {os.path.getsize(audio_path)} байт")
        
        # Определяем content-type по расширению файла
        file_ext = os.path.splitext(audio_path)[1].lower()
        content_type = "audio/m4a"  # По умолчанию
        if file_ext == ".ogg":
            content_type = "audio/ogg"
        elif file_ext == ".m4a":
            content_type = "audio/m4a"
        elif file_ext == ".mp3":
            content_type = "audio/mpeg"
        elif file_ext == ".wav":
            content_type = "audio/wav"
        
        # Бэкенд ожидает файл с именем "audio.m4a", но принимает любой формат
        with open(audio_path, "rb") as f:
            files = {"audio": ("audio.m4a", f, content_type)}
            resp = requests.post(upload_url, files=files, timeout=30)
        
        print(f"[Backend] Ответ на загрузку: статус {resp.status_code}")
        if resp.status_code == 200:
            data = resp.json() or {}
            recording_id = data.get("recording_id")
            if recording_id:
                print(f"[Backend] Получен recording_id: {recording_id}")
                return recording_id
            else:
                print(f"[Backend] Не получен recording_id в ответе: {data}")
                return None
        else:
            print(f"[Backend] Ошибка загрузки: {resp.status_code} {resp.text[:200]}")
            return None
    except Exception as e:
        print(f"[Backend] Исключение при загрузке: {e}")
        import traceback
        traceback.print_exc()
        return None


def format_text_with_chatgpt(text: str) -> Optional[str]:
    """Форматирует текст через ChatGPT API бэкенда. Возвращает отформатированный текст или None."""
    try:
        base_url = (config["backend"]["base_url"]).rstrip("/")
        chat_url = f"{base_url}/api/chat"
        
        # Промпт для форматирования транскрипции
        prompt = f"""Отформатируй следующую транскрипцию аудио сообщения. Сделай текст читабельным:
- Разбей на абзацы по смыслу
- Добавь правильную пунктуацию
- Исправь очевидные ошибки распознавания
- Сохрани оригинальный смысл и стиль

Транскрипция:
{text}"""
        
        print(f"[ChatGPT] Отправляю запрос на форматирование: {chat_url}")
        resp = requests.post(
            chat_url,
            json={"question": prompt},
            headers={"Content-Type": "application/json"},
            timeout=60
        )
        
        print(f"[ChatGPT] Ответ: статус {resp.status_code}")
        if resp.status_code == 200:
            data = resp.json() or {}
            formatted_text = data.get("answer") or ""
            if formatted_text:
                print(f"[ChatGPT] Получен отформатированный текст: {len(formatted_text)} символов")
                return formatted_text
            else:
                print(f"[ChatGPT] Пустой ответ от ChatGPT")
                return None
        else:
            print(f"[ChatGPT] Ошибка: {resp.status_code} {resp.text[:200]}")
            return None
    except Exception as e:
        print(f"[ChatGPT] Исключение: {e}")
        import traceback
        traceback.print_exc()
        return None


def create_short_summary_with_chatgpt(text: str) -> Optional[str]:
    """Создает короткую версию текста через ChatGPT API бэкенда. Возвращает краткое саммари или None."""
    try:
        base_url = (config["backend"]["base_url"]).rstrip("/")
        chat_url = f"{base_url}/api/chat"
        
        # Промпт для создания короткой версии
        prompt = f"""Создай короткую версию следующего текста.
Пиши от лица того, кто написал сообщение, как будто ты сам являешься этим человеком и решил написать сообщение коротко и лаконично.
Подумай как сказать все что написано в изначальном тексте, но короче, понятнее и без воды.
Самое важное сохранить информацию и смысл, но убрать все лишнее, что отвлекает от сути
Подсказки:
- Убери все лишние слова: вводные слова, слова-паразиты, повторения, воду
- Структурируй информацию (используй списки, абзацы)
- Убери эмоциональные вставки

Текст:
{text}"""
        
        print(f"[ChatGPT] Отправляю запрос на создание короткой версии: {chat_url}")
        resp = requests.post(
            chat_url,
            json={"question": prompt},
            headers={"Content-Type": "application/json"},
            timeout=60
        )
        
        print(f"[ChatGPT] Ответ на короткую версию: статус {resp.status_code}")
        if resp.status_code == 200:
            data = resp.json() or {}
            short_text = data.get("answer") or ""
            if short_text:
                print(f"[ChatGPT] Получена короткая версия: {len(short_text)} символов")
                return short_text
            else:
                print(f"[ChatGPT] Пустой ответ на короткую версию")
                return None
        else:
            print(f"[ChatGPT] Ошибка короткой версии: {resp.status_code} {resp.text[:200]}")
            return None
    except Exception as e:
        print(f"[ChatGPT] Исключение при создании короткой версии: {e}")
        import traceback
        traceback.print_exc()
        return None


def poll_transcription_from_backend(recording_id: str, timeout_seconds: int = 180) -> Optional[str]:
    """Опрашивает бэкенд для получения транскрипции. Возвращает текст или None."""
    try:
        base_url = (config["backend"]["base_url"]).rstrip("/")
        poll_url = f"{base_url}/api/transcription/{recording_id}"
        
        print(f"[Backend] Начинаю опрос транскрипции: {poll_url}")
        
        started = time.time()
        poll_interval = 0.5  # Начинаем с 0.5 секунды
        max_interval = 3.0   # Максимум 3 секунды между запросами
        
        while True:
            if time.time() - started > timeout_seconds:
                print(f"[Backend] Таймаут опроса ({timeout_seconds} секунд)")
                return None
            
            time.sleep(poll_interval)
            
            resp = requests.get(poll_url, timeout=10)
            print(f"[Backend] Статус опроса: {resp.status_code}")
            
            if resp.status_code == 404:
                print(f"[Backend] Job не найден (404)")
                return None
            
            if resp.status_code != 200:
                print(f"[Backend] Ошибка опроса: {resp.status_code} {resp.text[:200]}")
                poll_interval = min(poll_interval * 1.5, max_interval)
                continue
            
            data = resp.json() or {}
            status = (data.get("status") or "").lower()
            
            print(f"[Backend] Получен статус: {status}, данные: {list(data.keys())}")
            
            if status == "ready":
                transcription = data.get("transcription") or ""
                print(f"[Backend] Транскрипция получена: {len(transcription)} символов")
                return transcription if transcription else None
            elif status == "error":
                error_msg = data.get("error") or "Ошибка транскрибации"
                print(f"[Backend] Ошибка транскрибации от бэкенда: {error_msg}")
                # Сохраняем ошибку для показа пользователю
                return f"ERROR:{error_msg}"
            elif status == "processing":
                # Увеличиваем интервал опроса
                poll_interval = min(poll_interval * 1.5, max_interval)
                continue
            else:
                print(f"[Backend] Неизвестный статус: {status}, полный ответ: {data}")
                poll_interval = min(poll_interval * 1.5, max_interval)
                continue
                
    except Exception as e:
        print(f"[Backend] Исключение при опросе: {e}")
        import traceback
        traceback.print_exc()
        return None


async def handle_text_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Обработчик текстовых сообщений"""
    message = update.message
    if message and message.text:
        await message.reply_text(
            "👋 Привет! Отправь мне голосовое сообщение или аудио файл, и я сделаю транскрипцию.\n\n"
            "Используй /help для получения справки."
        )


async def process_audio(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Обработчик голосовых сообщений и аудио файлов"""
    message = update.message
    if not message:
        return
    
    # Проверяем, есть ли голосовое сообщение (основной случай)
    if message.voice:
        print(f"🎤 Получено голосовое сообщение (длительность: {message.voice.duration}с, размер: {message.voice.file_size} байт)")
        file = await context.bot.get_file(message.voice.file_id)
        file_extension = "ogg"  # Голосовые сообщения в Telegram всегда в формате OGG
    # Проверяем аудио файл
    elif message.audio:
        print(f"🎵 Получен аудио файл: {message.audio.file_name or 'без имени'}")
        file = await context.bot.get_file(message.audio.file_id)
        # Определяем расширение из имени файла или используем m4a по умолчанию
        if message.audio.file_name:
            ext = os.path.splitext(message.audio.file_name)[1].lstrip(".")
            file_extension = ext if ext else "m4a"
        else:
            file_extension = "m4a"
    # Проверяем документ (аудио файл отправлен как документ)
    elif message.document:
        mime_type = getattr(message.document, 'mime_type', None)
        if mime_type and mime_type.startswith("audio/"):
            print(f"📄 Получен аудио документ: {message.document.file_name or 'без имени'}, mime_type={mime_type}")
            file = await context.bot.get_file(message.document.file_id)
            # Определяем расширение из имени файла
            if message.document.file_name:
                ext = os.path.splitext(message.document.file_name)[1].lstrip(".")
                file_extension = ext if ext else "m4a"
            else:
                file_extension = "m4a"
        else:
            # Это не аудио документ, игнорируем
            return
    else:
        # Неизвестный тип, игнорируем
        return
    
    # Отправляем саммари перед началом обработки
    duration_info = ""
    if message.voice:
        duration = message.voice.duration
        duration_info = f" ({duration}с)"
    elif message.audio:
        duration = getattr(message.audio, 'duration', None)
        if duration:
            duration_info = f" ({duration}с)"
    
    status_message = await message.reply_text(f"🎤 Получено аудио сообщение{duration_info}\n🔄 Начинаю обработку...")
    
    try:

        # Создаём уникальное имя файла
        job_id = str(uuid.uuid4())
        
        audio_path = os.path.join(DATA_DIR, f"{job_id}.{file_extension}")
        
        # Скачиваем файл
        print(f"📥 Скачиваю файл в: {audio_path}")
        await status_message.edit_text(f"🎤 Получено аудио сообщение{duration_info}\n📥 Скачиваю файл...")
        await file.download_to_drive(custom_path=audio_path)
        
        # Проверяем, что файл скачался
        if not os.path.exists(audio_path):
            await status_message.edit_text("❌ Ошибка: файл не был скачан.")
            return
        
        file_size = os.path.getsize(audio_path)
        print(f"✅ Файл скачан, размер: {file_size} байт")
        
        # Обновляем статус
        await status_message.edit_text(f"🎤 Получено аудио сообщение{duration_info}\n🔄 Загружаю на бэкенд...")
        
        # Загружаем файл на бэкенд через API (как фронтенд)
        recording_id = upload_audio_to_backend(audio_path)
        
        if not recording_id:
            await status_message.edit_text("❌ Ошибка: не удалось загрузить файл на бэкенд.")
            # Удаляем временный файл
            try:
                if os.path.exists(audio_path):
                    os.remove(audio_path)
            except OSError:
                pass
            return
        
        # Обновляем статус
        await status_message.edit_text(f"🎤 Получено аудио сообщение{duration_info}\n🔄 Делаю транскрипцию...")
        
        # Опрашиваем бэкенд для получения транскрипции (как фронтенд)
        print(f"🔄 Ожидаю транскрипцию для recording_id: {recording_id}")
        transcription = poll_transcription_from_backend(recording_id, timeout_seconds=180)
        
        print(f"📝 Результат транскрипции: {'получен' if transcription else 'не получен'}")
        
        # Удаляем временный файл
        try:
            if os.path.exists(audio_path):
                os.remove(audio_path)
        except OSError:
            pass
        
        # Отправляем результат
        if transcription:
            # Проверяем, не является ли это ошибкой от бэкенда
            if transcription.startswith("ERROR:"):
                error_msg = transcription[6:]  # Убираем префикс "ERROR:"
                await status_message.edit_text(f"❌ Ошибка транскрипции:\n\n{error_msg}")
            else:
                # Форматируем текст через ChatGPT
                await status_message.edit_text(f"🎤 Получено аудио сообщение{duration_info}\n✅ Транскрипция получена\n🎨 Форматирую текст...")
                
                formatted_text = format_text_with_chatgpt(transcription)
                
                if not formatted_text:
                    # Если форматирование не удалось, используем оригинальную транскрипцию
                    print("[ChatGPT] Форматирование не удалось, использую оригинальную транскрипцию")
                    formatted_text = transcription
                
                # Создаем короткую версию
                await status_message.edit_text(f"🎤 Получено аудио сообщение{duration_info}\n✅ Транскрипция получена\n📝 Создаю короткую версию...")
                
                short_version = create_short_summary_with_chatgpt(formatted_text)
                
                # Отправляем обе версии
                # Сначала короткую версию
                if short_version:
                    await message.reply_text(f"📋 **Короткая версия (саммари):**\n\n{short_version}", parse_mode="Markdown")
                else:
                    print("[ChatGPT] Создание короткой версии не удалось")
                    # Если короткая версия не получилась, отправляем только отформатированную
                
                # Затем полную отформатированную версию
                await message.reply_text(f"📄 **Полная версия (оригинал):**\n\n{formatted_text}", parse_mode="Markdown")
                
                # Удаляем статусное сообщение
                try:
                    await status_message.delete()
                except:
                    pass
        else:
            await status_message.edit_text("❌ Не удалось получить транскрипцию. Попробуй ещё раз.")
            
    except Exception as e:
        print(f"Ошибка обработки аудио: {e}")
        try:
            await status_message.edit_text(f"❌ Произошла ошибка: {str(e)}")
        except:
            await message.reply_text(f"❌ Произошла ошибка: {str(e)}")


def run_bot():
    """Запускает телеграм бота"""
    if not TELEGRAM_BOT_TOKEN:
        print("⚠️  Telegram bot token не найден в конфиге. Бот не будет запущен.")
        return
    
    try:
        print(f"🤖 Запускаю Telegram бота с токеном: {TELEGRAM_BOT_TOKEN[:10]}...")
        # Создаём приложение
        application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
        
        # Регистрируем обработчики
        application.add_handler(CommandHandler("start", start_command))
        application.add_handler(CommandHandler("help", help_command))
        # Обработчик голосовых сообщений (приоритет - это основной способ использования)
        application.add_handler(MessageHandler(
            filters.VOICE,
            process_audio
        ))
        # Обработчик аудио файлов (на случай если кто-то отправит как файл)
        application.add_handler(MessageHandler(
            filters.AUDIO,
            process_audio
        ))
        # Обработчик документов-аудио (на случай если кто-то отправит как документ)
        application.add_handler(MessageHandler(
            filters.Document.ALL,
            process_audio
        ))
        # Обработчик текстовых сообщений
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_message))
        
        # Запускаем бота - используем простой способ через run_polling
        # Но с отключенными сигналами для работы в потоке
        import asyncio
        import threading
        
        def run_bot_async():
            """Запускает бота в отдельном event loop"""
            try:
                # Создаём новый event loop для этого потока
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                
                print("✅ Telegram бот запущен и готов к работе!")
                
                # Запускаем бота через run_polling, но в отдельном потоке
                # Используем stop_signals=None чтобы не обрабатывать сигналы
                async def run():
                    await application.initialize()
                    await application.start()
                    await application.updater.start_polling(
                        allowed_updates=Update.ALL_TYPES,
                        drop_pending_updates=True
                    )
                    # Ждём бесконечно
                    await asyncio.Event().wait()
                
                # Запускаем в новом event loop
                loop.run_until_complete(run())
            except Exception as e:
                print(f"❌ Ошибка в боте: {e}")
                import traceback
                traceback.print_exc()
        
        # Запускаем в отдельном потоке
        bot_thread = threading.Thread(target=run_bot_async, daemon=True)
        bot_thread.start()
        print("🔄 Поток бота запущен...")
        
    except Exception as e:
        print(f"❌ Ошибка запуска Telegram бота: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    run_bot()


#!/usr/bin/env python3
"""Тестовый скрипт для проверки ключей AssemblyAI на транскрипцию

Использование:
    python test_assemblyai_key.py <API_KEY>
    python test_assemblyai_key.py "ваш-ключ-здесь"
"""

import requests
import json
import sys
import time

def test_assemblyai_key(api_key: str):
    """Проверяет ключ AssemblyAI через запрос к API"""
    print("🔍 Проверяю ключ AssemblyAI...")
    print(f"   Ключ: {api_key[:10]}...{api_key[-10:]}")
    
    headers = {
        "authorization": api_key,
        "content-type": "application/json",
    }
    
    # Проверяем доступ к API через создание тестовой транскрипции
    print("\n1️⃣ Проверка валидности ключа через создание транскрипции...")
    try:
        # Используем публичный тестовый аудиофайл для проверки
        # Это короткий тестовый файл от AssemblyAI
        payload = {
            "audio_url": "https://storage.googleapis.com/aai-docs-samples/test.mp3",
            "punctuate": True,
            "format_text": True,
            "language_detection": True,
        }
        
        print("   Создаю задачу транскрипции...")
        resp = requests.post(
            "https://api.assemblyai.com/v2/transcript",
            headers=headers,
            json=payload,
            timeout=30
        )
        
        if resp.status_code == 200:
            data = resp.json()
            transcript_id = data.get("id")
            if transcript_id:
                print(f"✅ Задача создана! ID: {transcript_id}")
                print("   Ключ валиден! (создание задачи подтверждает работоспособность)")
                print("   Ожидаю завершения транскрипции...")
                
                # Опрашиваем статус
                max_attempts = 10
                for attempt in range(max_attempts):
                    time.sleep(2)
                    poll_resp = requests.get(
                        f"https://api.assemblyai.com/v2/transcript/{transcript_id}",
                        headers=headers,
                        timeout=30
                    )
                    
                    if poll_resp.status_code == 200:
                        poll_data = poll_resp.json()
                        status = poll_data.get("status", "").lower()
                        
                        if status == "completed":
                            text = poll_data.get("text", "")
                            print(f"✅ Транскрипция завершена успешно!")
                            print(f"   Текст: {text[:100]}..." if len(text) > 100 else f"   Текст: {text}")
                            return True
                        elif status == "error":
                            error = poll_data.get("error", "Неизвестная ошибка")
                            # Если ошибка связана с файлом, а не с ключом - ключ работает
                            if "download" in error.lower() or "file" in error.lower() or "url" in error.lower():
                                print(f"⚠️  Ошибка связана с файлом (не с ключом): {error}")
                                print("   ✅ Ключ работает! Проблема только в тестовом файле.")
                                return True
                            else:
                                print(f"❌ Ошибка транскрипции: {error}")
                                return False
                        elif status in ["queued", "processing"]:
                            print(f"   Статус: {status} (попытка {attempt + 1}/{max_attempts})")
                            continue
                        else:
                            print(f"⚠️  Неизвестный статус: {status}")
                            continue
                    elif poll_resp.status_code == 401:
                        print("❌ Ошибка авторизации при опросе (401)")
                        return False
                    else:
                        print(f"⚠️  Ошибка при опросе: {poll_resp.status_code}")
                        print(f"   Ответ: {poll_resp.text[:200]}")
                        continue
                
                print("⚠️  Таймаут ожидания транскрипции")
                # Если задача создалась, ключ работает
                print("   ✅ Но ключ валиден (задача была создана)")
                return True
            else:
                print("❌ Не получен ID транскрипции")
                print(f"   Ответ: {resp.text[:200]}")
                return False
                
        elif resp.status_code == 401:
            print("❌ Ошибка: Ключ невалиден или истёк (401 Unauthorized)")
            print(f"   Ответ: {resp.text[:200]}")
            return False
        elif resp.status_code == 403:
            print("❌ Ошибка: Доступ запрещён (403 Forbidden)")
            print(f"   Ответ: {resp.text[:200]}")
            return False
        elif resp.status_code == 429:
            print("⚠️  Ошибка: Превышен лимит запросов (429)")
            print(f"   Ответ: {resp.text[:200]}")
            return False
        else:
            print(f"⚠️  Неожиданный статус: {resp.status_code}")
            print(f"   Ответ: {resp.text[:200]}")
            return False
            
    except requests.exceptions.Timeout:
        print("❌ Таймаут при запросе к API")
        return False
    except Exception as e:
        print(f"❌ Ошибка при проверке ключа: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("❌ Ошибка: Не указан ключ API")
        print("\nИспользование:")
        print(f"  python {sys.argv[0]} <API_KEY>")
        print(f"  python {sys.argv[0]} \"ваш-ключ-здесь\"")
        sys.exit(1)
    
    api_key = sys.argv[1].strip()
    
    if not api_key:
        print("❌ Ошибка: Ключ API пустой")
        sys.exit(1)
    
    success = test_assemblyai_key(api_key)
    if success:
        print("\n✅ ИТОГ: Ключ AssemblyAI работает для транскрипции!")
    else:
        print("\n❌ ИТОГ: Ключ AssemblyAI не работает или недоступен.")
    sys.exit(0 if success else 1)


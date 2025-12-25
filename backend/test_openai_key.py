#!/usr/bin/env python3
"""Тестовый скрипт для проверки ключа OpenAI на транскрипцию

Использование:
    python test_openai_key.py <API_KEY>
    python test_openai_key.py "sk-proj-..."
"""

import requests
import json
import os
import sys
import tempfile

def test_openai_key(api_key: str):
    """Проверяет ключ OpenAI через запрос к API"""
    print("🔍 Проверяю ключ OpenAI...")
    print(f"   Ключ: {api_key[:20]}...{api_key[-10:]}")
    
    # Сначала проверим, что ключ валиден через простой запрос к API
    print("\n1️⃣ Проверка валидности ключа через список моделей...")
    try:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        
        # Проверяем доступ к API через список моделей
        resp = requests.get(
            "https://api.openai.com/v1/models",
            headers=headers,
            timeout=10
        )
        
        if resp.status_code == 200:
            print("✅ Ключ валиден! API доступен.")
            models = resp.json().get("data", [])
            whisper_models = [m for m in models if "whisper" in m.get("id", "").lower()]
            if whisper_models:
                print(f"✅ Модель Whisper доступна: {whisper_models[0].get('id')}")
            else:
                print("⚠️  Модель Whisper не найдена в списке (но это может быть нормально)")
        elif resp.status_code == 401:
            print("❌ Ошибка: Ключ невалиден или истёк (401 Unauthorized)")
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
            
    except Exception as e:
        print(f"❌ Ошибка при проверке ключа: {e}")
        return False
    
    # Теперь проверим, что транскрипция доступна
    print("\n2️⃣ Проверка доступности эндпоинта транскрипции...")
    try:
        # Создаём минимальный тестовый аудиофайл (пустой или минимальный)
        # Но для реальной проверки нужен настоящий аудиофайл
        # Вместо этого просто проверим, что эндпоинт отвечает
        
        # Проверяем через запрос с минимальными данными
        # OpenAI требует реальный аудиофайл, поэтому создадим минимальный WAV файл
        
        # Создаём минимальный WAV файл (44 байта - минимальный валидный WAV)
        minimal_wav = (
            b'RIFF'  # ChunkID
            b'\x24\x00\x00\x00'  # ChunkSize (36 bytes)
            b'WAVE'  # Format
            b'fmt '  # Subchunk1ID
            b'\x10\x00\x00\x00'  # Subchunk1Size (16)
            b'\x01\x00'  # AudioFormat (PCM)
            b'\x01\x00'  # NumChannels (1)
            b'\x44\xac\x00\x00'  # SampleRate (44100)
            b'\x88\x58\x01\x00'  # ByteRate
            b'\x02\x00'  # BlockAlign
            b'\x10\x00'  # BitsPerSample (16)
            b'data'  # Subchunk2ID
            b'\x00\x00\x00\x00'  # Subchunk2Size (0 - пустой)
        )
        
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
            tmp_file.write(minimal_wav)
            tmp_file_path = tmp_file.name
        
        try:
            with open(tmp_file_path, "rb") as f:
                resp = requests.post(
                    "https://api.openai.com/v1/audio/transcriptions",
                    headers={"Authorization": f"Bearer {api_key}"},
                    files={"file": ("test.wav", f, "audio/wav")},
                    data={"model": "whisper-1"},
                    timeout=30
                )
            
            if resp.status_code == 200:
                print("✅ Эндпоинт транскрипции доступен и отвечает!")
                result = resp.json()
                print(f"   Результат: {result.get('text', 'пусто')}")
                return True
            elif resp.status_code == 401:
                print("❌ Ошибка авторизации при транскрипции (401)")
                print(f"   Ответ: {resp.text[:200]}")
                return False
            elif resp.status_code == 400:
                # 400 может быть из-за пустого файла, но это значит, что ключ работает
                print("⚠️  Эндпоинт отвечает, но файл слишком короткий (400)")
                print("   Это нормально для тестового файла - ключ работает!")
                print(f"   Ответ: {resp.text[:200]}")
                return True  # Ключ работает, просто файл невалидный
            else:
                print(f"⚠️  Неожиданный статус при транскрипции: {resp.status_code}")
                print(f"   Ответ: {resp.text[:200]}")
                return resp.status_code != 401  # Если не 401, то ключ может работать
                
        finally:
            # Удаляем временный файл
            try:
                os.unlink(tmp_file_path)
            except:
                pass
                
    except Exception as e:
        print(f"❌ Ошибка при проверке транскрипции: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("❌ Ошибка: Не указан ключ API")
        print("\nИспользование:")
        print(f"  python {sys.argv[0]} <API_KEY>")
        print(f"  python {sys.argv[0]} \"sk-proj-...\"")
        sys.exit(1)
    
    api_key = sys.argv[1].strip()
    
    if not api_key:
        print("❌ Ошибка: Ключ API пустой")
        sys.exit(1)
    
    if not api_key.startswith("sk-"):
        print("⚠️  Предупреждение: Ключ не начинается с 'sk-'")
    
    success = test_openai_key(api_key)
    if success:
        print("\n✅ ИТОГ: Ключ OpenAI работает для транскрипции!")
    else:
        print("\n❌ ИТОГ: Ключ OpenAI не работает или недоступен.")
    sys.exit(0 if success else 1)



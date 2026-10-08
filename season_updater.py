import os
import json
import requests

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def fetch_reddit_via_serper():
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не найден в секретах GitHub!")
        return None
        
    url = "https://google.serper.dev/search"
    payload = json.dumps({
        "q": "FH6 Series 6 Summer Festival Playlist Guide",
        "num": 5
    })
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    
    try:
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            results_text = ""
            for item in data.get('organic', []):
                title = item.get('title', '')
                snippet = item.get('snippet', '')
                results_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {snippet}\n\n"
            print(f"Найдено результатов поиска: {len(results_text)}")
            return results_text
        print(f"Ошибка Serper API: {response.status_code}")
        return None
    except Exception as e:
        print(f"Ошибка запроса к Serper: {e}")
        return None

def update_playlist_json(search_context):
    if not search_context or len(search_context.strip()) < 10:
        print("Контекст поиска пуст.")
        return False

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — парсер данных для базы аукциона Forza Horizon.
    Проанализируйте результаты поиска Google и извлеките награды сезона Series 6 Summer для Forza Horizon 6.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    
    Шаблон JSON:
    {{
      "current_season": "SUMMER",
      "series_number": "Series 6: Horizon Meets",
      "series_rewards": "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1",
      "cars_20pts": [
        {{"name": "2000 Honda Prelude Type SH", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "1974 Toyota Corolla SR5", "est_value": "цены нет"}}
      ],
      "trading_advice": "Honda Prelude Type SH — эксклюзив старта 6-й серии. Выкупайте по низу рынка."
    }}

    Результаты поиска:
    {search_context}
    """

    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": "You are a strict JSON data extractor. Output ONLY raw valid JSON."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.1
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        if response.status_code == 200:
            result = response.json()['choices'][0]['message']['content'].strip()
            print(f"Ответ от DeepSeek: {result}")
            
            # Очистка от возможных маркdown-тегов
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            
            # Проверяем, что это валидный JSON, и сразу пишем в файл
            parsed_json = json.loads(result)
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(parsed_json, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json принудительно перезаписан и сохранен!")
            return True
        else:
            print(f"Ошибка DeepSeek API: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        print(f"Ошибка при обработке JSON: {e}")
        return False

if __name__ == "__main__":
    print("Запуск принудительного обновления...")
    search_data = fetch_reddit_via_serper()
    update_playlist_json(search_data)

import os
import json
import requests

# Ключ API, который уже настроен в ваших GitHub Secrets
DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_latest_reddit_playlist():
    # Reddit блокирует автоматические запросы без кастомного User-Agent
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
    
    # Ищем строго по флееру Festival Playlist, сортируем по самым новым
    url = 'https://www.reddit.com/r/ForzaHorizon/search.json?q=flair_name%3A"Festival%20Playlist"&restrict_sr=1&sort=new&limit=2'
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code == 200:
            data = response.json()
            posts_text = ""
            for post in data['data']['children']:
                title = post['data']['title']
                text = post['data']['selftext']
                posts_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {text}\n\n"
            return posts_text
        return None
    except Exception as e:
        print(f"Ошибка парсинга Reddit: {e}")
        return None

def update_playlist_json(reddit_context):
    if not reddit_context or len(reddit_context) < 50:
        return create_fallback_json()

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — парсер данных для базы аукциона Forza Horizon.
    Проанализируйте свежий пост с Reddit и извлеките награды текущего сезона.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json).
    ПРАВИЛО 2: Если текст не содержит четких наград, запишите "Ожидание данных FH6" и цену "0".
    
    Шаблон JSON:
    {{
      "current_season": "СЕЗОН (например, SUMMER)",
      "series_number": "Название серии",
      "series_rewards": "80 PTS: Машина 1, 160 PTS: Машина 2",
      "cars_20pts": [
        {{"name": "Машина за 20 PTS", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Машина за 40 PTS", "est_value": "цены нет"}}
      ],
      "trading_advice": "Краткий совет по снайпингу для этих наград"
    }}

    Текст с Reddit:
    {reddit_context}
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
            # Очистка на случай, если ИИ добавил маркдаун
            if result.startswith("```json"):
                result = result[7:-3].strip()
            
            # Проверяем на валидность
            parsed_json = json.loads(result)
            return parsed_json
        return create_fallback_json()
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
        return create_fallback_json()

def create_fallback_json():
    return {
      "current_season": "Ожидание данных FH6",
      "series_number": "Ожидание данных FH6",
      "series_rewards": "Ожидание данных FH6",
      "cars_20pts": [
        {"name": "Ожидание данных FH6", "est_value": "0"}
      ],
      "cars_40pts": [
        {"name": "Ожидание данных FH6", "est_value": "0"}
      ],
      "trading_advice": "Ожидание данных FH6"
    }

if __name__ == "__main__":
    print("Получение данных с Reddit r/ForzaHorizon...")
    reddit_data = fetch_latest_reddit_playlist()
    
    print("Генерация JSON через DeepSeek...")
    final_data = update_playlist_json(reddit_data)
    
    with open("playlist.json", "w", encoding="utf-8") as f:
        json.dump(final_data, f, ensure_ascii=False, indent=2)
        
    print("Файл playlist.json успешно обновлен.")

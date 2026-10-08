import os
import json
import requests

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_reddit_posts():
    # Используем прямую выдачу новых постов сабреддита (она не блокируется так жестко, как поиск)
    url = "https://www.reddit.com/r/ForzaHorizon/new.json?limit=25"
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=15)
        if response.status_code == 200:
            data = response.json()
            posts_text = ""
            for post in data.get('data', {}).get('children', []):
                title = post['data'].get('title', '')
                text = post['data'].get('selftext', '')
                # Собираем всё, что связано с сериями или плейлистами
                if any(k in title.lower() for k in ["series", "playlist", "reward", "fh6", "summer"]):
                    posts_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {text}\n\n"
            return posts_text
        return None
    except Exception as e:
        print(f"Ошибка получения данных с Reddit: {e}")
        return None

def update_playlist_json(reddit_context):
    if not reddit_context or len(reddit_context.strip()) < 20:
        print("Лента пуста или не содержит нужных постов.")
        return None

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — парсер данных для базы аукциона Forza Horizon.
    Проанализируйте тексты постов с Reddit и извлеките награды текущего сезона Series 6 для Forza Horizon 6.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json).
    ПРАВИЛО 2: Данные должны относиться к Forza Horizon 6 (FH6) и актуальной Series. Строго игнорируйте Forza Horizon 5 (FH5).
    ПРАВИЛО 3: Если в тексте нет конкретных машин за 20 PTS и 40 PTS для текущего сезона, верните пустой JSON с пустыми полями или null.
    
    Шаблон JSON:
    {{
      "current_season": "SUMMER",
      "series_number": "Series 6: Horizon Meets",
      "series_rewards": "80 PTS: 2025 BMW M4 CS, 160 PTS: 2015 Koenigsegg One:1",
      "cars_20pts": [
        {{"name": "Точное название машины за 20 PTS", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Точное название машины за 40 PTS", "est_value": "цены нет"}}
      ],
      "trading_advice": "Совет по снайпингу"
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
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            
            parsed_json = json.loads(result)
            # Проверяем, что ИИ действительно нашел машины, а не вернул заглушки
            if parsed_json.get("cars_20pts") and len(parsed_json["cars_20pts"]) > 0:
                if "Ожидание" not in parsed_json["cars_20pts"][0]["name"]:
                    return parsed_json
            return None
        return None
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
        return None

if __name__ == "__main__":
    print("Загрузка постов из ленты Reddit...")
    reddit_data = fetch_reddit_posts()
    final_data = update_playlist_json(reddit_data)
    
    if final_data:
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен автоматически.")
    else:
        print("Автоматическое обновление: в свежих постах ленты детальный гайд еще не найден, файл не трогаем.")

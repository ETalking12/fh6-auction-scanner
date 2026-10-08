import os
import json
import requests

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_reddit_posts():
    # Ищем конкретно по заголовкам с наградами и плейлистом через публичный JSON поиска Reddit
    url = "https://www.reddit.com/r/ForzaHorizon/search.json?q=title%3A(Series%20AND%20(Rewards%20OR%20Playlist%20OR%20Breakdown))&restrict_sr=1&sort=new&limit=5"
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code == 200:
            data = response.json()
            posts_text = ""
            for post in data.get('data', {}).get('children', []):
                title = post['data'].get('title', '')
                text = post['data'].get('selftext', '')
                posts_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {text}\n\n"
            return posts_text
        return None
    except Exception as e:
        print(f"Ошибка получения данных с Reddit: {e}")
        return None

def update_playlist_json(reddit_context):
    if not reddit_context or len(reddit_context.strip()) < 20:
        print("Reddit не вернул постов.")
        return None

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — парсер данных для базы аукциона Forza Horizon.
    Проанализируйте тексты постов с Reddit и извлеките награды текущего сезона Series 6.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json).
    ПРАВИЛО 2: Убедитесь, что данные относятся к актуальной серии (Series 6) и Forza Horizon 6. Игнорируйте любые упоминания Forza Horizon 5.
    ПРАВИЛО 3: Если в тексте нет информации о машинах сезона, верните пустой JSON.
    
    Шаблон JSON:
    {{
      "current_season": "SUMMER",
      "series_number": "Series 6",
      "series_rewards": "Описание наград серии",
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
            return parsed_json
        return None
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
        return None

if __name__ == "__main__":
    reddit_data = fetch_reddit_posts()
    final_data = update_playlist_json(reddit_data)
    
    if final_data and "cars_20pts" in final_data:
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен автоматически.")
    else:
        print("Автоматическое обновление пропущено: нет валидных данных в выдаче.")

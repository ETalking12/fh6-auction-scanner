import os
import json
import requests

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_reddit_posts():
    # Забираем свежие посты из ленты сабреддита
    url = "https://www.reddit.com/r/ForzaHorizon/new.json?limit=15"
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
        return None

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — строгий парсер данных для базы аукциона Forza Horizon. Ваша главная задача — извлекать награды ТОЛЬКО для Forza Horizon 6 (FH6).
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json).
    ПРАВИЛО 2 (АНТИ-FH5): Внимательно проверяйте текст постов. Если в заголовке или тексте упоминается Forza Horizon 5, FH5, Horizon 5 или любые старые части — КАТЕГОРИЧЕСКИ игнорируйте этот пост. Данные должны относиться исключительно к Forza Horizon 6 (FH6).
    ПРАВИЛО 3: Извлекайте данные только если найден актуальный сезонный гайд (Series, Festival Playlist, Rewards).
    ПРАВИЛО 4: Если в ленте нет подходящих свежих постов именно по FH6, вы должны вернуть СТРОГО строку "SKIP" в поле current_season, чтобы мы не перезаписывали текущие данные.
    
    Шаблон JSON (если данные найдены):
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
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            
            parsed_json = json.loads(result)
            
            # Если ИИ вернул метку пропуска или обнаружил старую версию
            if parsed_json.get("current_season") == "SKIP" or "FH5" in str(parsed_json):
                print("Актуальных данных по FH6 не обнаружено (либо это FH5). Файл не трогаем.")
                return None
                
            return parsed_json
        return None
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
        return None

if __name__ == "__main__":
    reddit_data = fetch_reddit_posts()
    final_data = update_playlist_json(reddit_data)
    
    if final_data:
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен.")
    else:
        print("Пропуск обновления: защищаемся от перезаписи старыми данными или FH5.")

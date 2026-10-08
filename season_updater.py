import os
import json
import requests

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_official_playlist():
    # Официальный адрес плейлистов Forza
    url = "https://forza.net/fh6playlists"
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=15)
        if response.status_code == 200:
            return response.text
        print(f"Ошибка HTTP: {response.status_code}")
        return None
    except Exception as e:
        print(f"Ошибка загрузки страницы Forza.net: {e}")
        return None

def update_playlist_json(html_context):
    if not html_context or len(html_context.strip()) < 100:
        print("Получена слишком короткая страница или пустой ответ.")
        return None

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — парсер официального сайта Forza Horizon. Проанализируйте HTML-код страницы официального плейлиста и извлеките награды текущего летнего сезона (Summer) для Series 6.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json).
    ПРАВИЛО 2: Найдите точные названия машин за 20 PTS и 40 PTS текущего сезона.
    ПРАВИЛО 3: Если данные на странице скрыты за скриптами или отсутствуют, верните пустой JSON.
    
    Шаблон JSON:
    {{
      "current_season": "SUMMER",
      "series_number": "Series 6",
      "series_rewards": "Награды серии",
      "cars_20pts": [
        {{"name": "Точное название машины за 20 PTS", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Точное название машины за 40 PTS", "est_value": "цены нет"}}
      ],
      "trading_advice": "Официальный сезонный плейлист FH6"
    }}

    HTML-код страницы:
    {html_context[:15000]}
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
            if parsed_json.get("cars_20pts") and len(parsed_json["cars_20pts"]) > 0:
                if "Ожидание" not in parsed_json["cars_20pts"][0]["name"]:
                    return parsed_json
            return None
        return None
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
        return None

if __name__ == "__main__":
    print("Загрузка данных с официального сайта Forza.net...")
    html_data = fetch_official_playlist()
    final_data = update_playlist_json(html_data)
    
    if final_data:
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен с официального сайта!")
    else:
        print("Не удалось извлечь данные (сайт использует динамическую подгрузку JS).")

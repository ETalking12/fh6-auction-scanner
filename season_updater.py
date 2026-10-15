import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def fetch_latest_playlist_info():
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не найден в секретах GitHub!")
        return None
        
    # Ищем конкретно осенний сезон 6-й серии
    query = "FH6 Series 6 Autumn Playlist Rewards"
    print(f"Поисковый запрос: {query}")
    
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    payload = json.dumps({"q": query, "num": 5})
    
    try:
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            results_text = ""
            for item in data.get('organic', []):
                snippet = item.get('snippet', '')
                results_text += f"{snippet}\n"
            return results_text
    except Exception as e:
        print(f"Ошибка поиска: {e}")
    return "Series 6 Autumn season active rewards"

def update_playlist_json(search_context):
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    # Жестко задаем текущий период, который мы уже знаем из Google-обзора
    current_season = "AUTUMN"
    series_number = "Series 6"

    prompt = f"""
    Вы — парсер данных для базы аукциона Forza Horizon 6.
    Сформируйте актуальный JSON для текущего сезона: {current_season}, {series_number} (Horizon Meets).
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    
    Шаблон JSON:
    {{
      "current_season": "{current_season}",
      "series_number": "{series_number}: Horizon Meets",
      "series_rewards": "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1",
      "cars_20pts": [
        {{"name": "Название машины за 20 очков в осеннем сезоне Series 6", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Название машины за 40 очков в осеннем сезоне Series 6", "est_value": "цены нет"}}
      ],
      "trading_advice": "Совет по трейдингу для машин 6-й серии Autumn."
    }}

    Контекст из интернета:
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
            
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            
            new_parsed_json = json.loads(result)
            
            # Добавляем штамп времени для гарантированного коммита
            new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json успешно обновлен!")
            return True
    except Exception as e:
        print(f"Ошибка: {e}")
    return False

if __name__ == "__main__":
    search_data = fetch_latest_playlist_info()
    update_playlist_json(search_data)

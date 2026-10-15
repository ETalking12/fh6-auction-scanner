import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def fetch_latest_playlist_info():
    """
    Делает точный поисковый запрос для поиска реальных гайдов и списков машин с Reddit и игровых сайтов.
    """
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не найден в секретах GitHub!")
        return None
        
    # Запрос нацелен на поиск конкретного гайда текущей недели
    query = "FH6 Series 6 Autumn Festival Playlist Guide Reddit"
    print(f"Поисковый запрос: {query}")
    
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    payload = json.dumps({"q": query, "num": 5})
    
    for attempt in range(3):
        try:
            response = requests.post(url, headers=headers, data=payload, timeout=15)
            if response.status_code == 200:
                data = response.json()
                results_text = ""
                
                # Собираем все тексты из органической выдачи (гайды, обсуждения)
                for item in data.get('organic', []):
                    if isinstance(item, dict):
                        title = item.get('title', '')
                        snippet = item.get('snippet', '')
                        results_text += f"ИСТОЧНИК: {title}\nТЕКСТ: {snippet}\n\n"
                
                if len(results_text.strip()) > 30:
                    print(f"Успешно собрано контекста: {len(results_text)} символов")
                    return results_text
            break
        except Exception as e:
            print(f"Попытка {attempt + 1} не удалась: {e}")
            time.sleep(2)
            
    print("Не удалось собрать данные из поиска, используем базовые ключевые слова.")
    return "Series 6 Autumn Festival Playlist rewards and cars"

def update_playlist_json(search_context):
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    current_season = "AUTUMN"
    series_number = "Series 6"

    prompt = f"""
    Вы — профессиональный парсер данных для базы аукциона Forza Horizon 6.
    Проанализируйте тексты из интернета ниже и извлеките СТОПРОЦЕНТНО РЕАЛЬНЫЕ названия автомобилей, которые раздаются в качестве наград за 20 очков (cars_20pts) и 40 очков (cars_40pts) в осеннем сезоне Series 6 (Horizon Meets).
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    ПРАВИЛО 3: Если в тексте есть точные названия машин из текущего осеннего плейлиста — впишите их.
    
    Шаблон JSON:
    {{
      "current_season": "{current_season}",
      "series_number": "{series_number}: Horizon Meets",
      "series_rewards": "Укажите награды 80 PTS и 160 PTS из текстов",
      "cars_20pts": [
        {{"name": "Точное название машины за 20 очков", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Точное название машины за 40 очков", "est_value": "цены нет"}}
      ],
      "trading_advice": "Точный совет по трейдингу для осеннего сезона Series 6 на основе гайдов."
    }}

    Тексты из поисковых гайдов:
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
            
            # Добавляем штамп времени для гарантированного коммита в Git
            new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json успешно обновлен на основе реальных гайдов!")
            return True
    except Exception as e:
        print(f"Ошибка при обработке: {e}")
    return False

if __name__ == "__main__":
    search_data = fetch_latest_playlist_info()
    update_playlist_json(search_data)

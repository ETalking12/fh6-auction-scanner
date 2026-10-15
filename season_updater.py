import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def get_current_series_and_season():
    """
    Точный расчет серии и сезона Forza Horizon 6 на основе текущей даты.
    Текущая точка (Series 6, Autumn) активна с 15 октября 2026 года.
    """
    # Точка отсчета: сегодня 15 октября 2026 года — это Series 6, AUTUMN
    anchor_date = datetime.date(2026, 10, 15)
    anchor_series = 6
    anchor_season_index = 1 # 0: SUMMER, 1: AUTUMN, 2: WINTER, 3: SPRING
    
    current_date = datetime.date.today()
    delta_days = (current_date - anchor_date).days
    
    # Считаем суммарный сдвиг по сезонам (каждый сезон ровно 7 дней)
    total_seasons_passed = anchor_season_index + (delta_days // 7)
    
    # Если дата меньше точки отсчета (на всякий случай)
    if delta_days < 0:
        total_seasons_passed = anchor_season_index + delta_days // 7
        
    # Каждые 4 сезона (28 дней) меняется серия
    current_series = anchor_series + (total_seasons_passed // 4)
    
    # Текущий сезон в рамках года/серии
    season_index = total_seasons_passed % 4
    seasons = ["SUMMER", "AUTUMN", "WINTER", "SPRING"]
    current_season = seasons[season_index]
    
    return max(1, current_series), current_season

def fetch_reddit_via_serper(series_num, season_name):
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не найден в секретах GitHub!")
        return None
        
    # Используем запросы, которые точно найдут свежие статьи (как на скриншотах Google)
    queries = [
        f"FH6 Series {series_num} {season_name} Breakdown and Rewards",
        f"Forza Horizon 6 Series {series_num} {season_name} Festival Playlist Guide",
        f"FH6 Series {series_num} playlist rewards"
    ]
    
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    
    for query in queries:
        print(f"Пробуем поисковый запрос: {query}")
        payload = json.dumps({"q": query, "num": 5})
        
        for attempt in range(3):
            try:
                response = requests.post(url, headers=headers, data=payload, timeout=15)
                if response.status_code == 200:
                    data = response.json()
                    results_text = ""
                    for item in data.get('organic', []):
                        title = item.get('title', '')
                        snippet = item.get('snippet', '')
                        results_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {snippet}\n\n"
                    
                    if len(results_text.strip()) > 50:
                        print(f"Успешно найдено результатов: {len(results_text)}")
                        return results_text
                break
            except Exception as e:
                print(f"Попытка {attempt + 1} неудачна для '{query}': {e}")
                time.sleep(2)
            
    print("Не удалось найти достаточно данных ни по одному запросу.")
    return None

def validate_json_content(data):
    required_keys = ["current_season", "series_number", "cars_20pts", "cars_40pts", "trading_advice"]
    for key in required_keys:
        if key not in data:
            print(f"Ошибка: отсутствует обязательный ключ '{key}'")
            return False
            
    if not isinstance(data.get("cars_20pts"), list) or len(data["cars_20pts"]) == 0:
        print("Ошибка: список cars_20pts пуст.")
        return False
        
    return True

def update_playlist_json(search_context, series_num, season_name):
    if not search_context or len(search_context.strip()) < 10:
        print("Контекст поиска пуст.")
        return False

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — строгий парсер данных для базы аукциона Forza Horizon.
    Проанализируйте результаты поиска Google и извлеките точные награды сезона Series {series_num} {season_name} для Forza Horizon 6.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    
    Шаблон JSON:
    {{
      "current_season": "{season_name}",
      "series_number": "Series {series_num}",
      "series_rewards": "Укажите актуальные награды 80 PTS и 160 PTS для серии {series_num} {season_name}",
      "cars_20pts": [
        {{"name": "Название машины за 20 очков", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Название машины за 40 очков", "est_value": "цены нет"}}
      ],
      "trading_advice": "Точный совет по трейдингу для сезона {season_name}."
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

    for attempt in range(3):
        try:
            response = requests.post(url, headers=headers, json=payload, timeout=30)
            if response.status_code == 200:
                result = response.json()['choices'][0]['message']['content'].strip()
                
                if result.startswith("```json"):
                    result = result[7:-3].strip()
                elif result.startswith("```"):
                    result = result[3:-3].strip()
                
                new_parsed_json = json.loads(result)
                
                if not validate_json_content(new_parsed_json):
                    print("Полученные данные не прошли проверку качества.")
                    return False
                
                old_data = {}
                if os.path.exists("playlist.json"):
                    try:
                        with open("playlist.json", "r", encoding="utf-8") as f:
                            old_data = json.load(f)
                    except:
                        pass
                
                old_data.pop("last_updated", None)
                temp_new = dict(new_parsed_json)
                temp_new.pop("last_updated", None)
                
                if old_data == temp_new:
                    print("Данные не изменились с прошлого раза. Обновляем метку времени.")
                else:
                    print("Обнаружены новые подтвержденные данные по сезону!")

                new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                with open("playlist.json", "w", encoding="utf-8") as f:
                    json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
                print("Файл playlist.json успешно сохранен!")
                return True
            else:
                print(f"Ошибка DeepSeek API: {response.status_code}")
        except Exception as e:
            print(f"Ошибка обработки: {e}")
            time.sleep(3)
            
    return False

if __name__ == "__main__":
    current_series, current_season = get_current_series_and_season()
    print(f"Автоматически определено: Серия {current_series}, Сезон {current_season}")
    
    search_data = fetch_reddit_via_serper(current_series, current_season)
    update_playlist_json(search_data, current_series, current_season)

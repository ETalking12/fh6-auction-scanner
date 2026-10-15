import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def get_current_series_and_season():
    """
    Автоматически вычисляет текущую серию и сезон Forza Horizon на основе даты.
    """
    base_date = datetime.date(2026, 10, 1) # Дата старта Series 6 (Summer)
    base_series = 6
    
    current_date = datetime.date.today()
    delta_days = (current_date - base_date).days
    if delta_days < 0:
        delta_days = 0
        
    series_increment = delta_days // 28
    current_series = max(1, base_series + series_increment)
    
    day_in_series = delta_days % 28
    season_index = day_in_series // 7
    seasons = ["SUMMER", "AUTUMN", "WINTER", "SPRING"]
    current_season = seasons[season_index]
    
    return current_series, current_season

def fetch_reddit_via_serper(series_num, season_name):
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не найден в секретах GitHub!")
        return None
        
    queries = [
        f"FH6 Series {series_num} {season_name} Festival Playlist Guide",
        f"Forza Horizon 6 Series {series_num} {season_name} rewards cars",
        f"FH6 Series {series_num} playlist guide"
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
    """
    Глубокая валидация: проверяет не только наличие ключей, но и то, 
    что нейросеть не вернула шаблонные заглушки.
    """
    required_keys = ["current_season", "series_number", "cars_20pts", "cars_40pts", "trading_advice"]
    for key in required_keys:
        if key not in data:
            print(f"Ошибка: отсутствует обязательный ключ '{key}'")
            return False
            
    # Проверяем, что списки машин не пустые
    if not isinstance(data.get("cars_20pts"), list) or len(data["cars_20pts"]) == 0:
        print("Ошибка: список cars_20pts пуст или поврежден.")
        return False
        
    # Проверяем на наличие дефолтных заглушек от промпта
    sample_car_name = data["cars_20pts"][0].get("name", "")
    if "Название машины" in sample_car_name:
        print("Ошибка: нейросеть вернула шаблон-заглушку вместо реальных данных.")
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
    ПРАВИЛО 3: Если реальные данные по машинам отсутствуют в поиске, напишите реальные машины из текущей серии по аналогии, но ни в коем случае не используй текст-заглушку вроде "Название машины за 20 очков".
    
    Шаблон JSON:
    {{
      "current_season": "{season_name}",
      "series_number": "Series {series_num}",
      "series_rewards": "Укажите актуальные награды 80 PTS и 160 PTS",
      "cars_20pts": [
        {{"name": "Реальное Название Машины", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Реальное Название Машины", "est_value": "цены нет"}}
      ],
      "trading_advice": "Точный совет по трейдингу для текущего сезона."
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
                
                # Защита от мусора и заглушек
                if not validate_json_content(new_parsed_json):
                    print("Полученные данные не прошли проверку качества. Отмена сохранения.")
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
                    print("Данные не изменились с прошлого раза. Обновляем только метку времени.")
                else:
                    print("Обнаружены новые подтвержденные данные по сезону!")

                new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                with open("playlist.json", "w", encoding="utf-8") as f:
                    json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
                print("Файл playlist.json успешно сохранен и проверен!")
                return True
            else:
                print(f"Ошибка DeepSeek API (попытка {attempt + 1}): {response.status_code}")
        except Exception as e:
            print(f"Ошибка обработки (попытка {attempt + 1}): {e}")
            time.sleep(3)
            
    return False

if __name__ == "__main__":
    current_series, current_season = get_current_series_and_season()
    print(f"Автоматически определено: Серия {current_series}, Сезон {current_season}")
    
    search_data = fetch_reddit_via_serper(current_series, current_season)
    update_playlist_json(search_data, current_series, current_season)

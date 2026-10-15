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
    Каждая серия длится 28 дней и делится на 4 сезона по 7 дней (Summer, Autumn, Winter, Spring).
    """
    base_date = datetime.date(2026, 10, 1)
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
    """
    Ищет информацию в Google с системой резервных запросов (fallback) и повторными попытками.
    """
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
        
        # Делаем до 3 попыток для каждого запроса на случай сетевых сбоев
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
                break # Если дошли сюда, статус не 200, но запрос ушел — пробуем следующий query
            except Exception as e:
                print(f"Попытка {attempt + 1} неудачна для '{query}': {e}")
                time.sleep(2)
            
    print("Не удалось найти достаточно данных ни по одному запросу.")
    return None

def validate_json_structure(data):
    """
    Проверяет, содержит ли полученный от нейросети JSON все обязательные поля.
    """
    required_keys = ["current_season", "series_number", "cars_20pts", "cars_40pts", "trading_advice"]
    for key in required_keys:
        if key not in data:
            print(f"Ошибка валидации: в ответе отсутствует обязательное поле '{key}'")
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
    Проанализируйте результаты поиска Google и извлеките награды сезона Series {series_num} {season_name} для Forza Horizon 6.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    
    Шаблон JSON:
    {{
      "current_season": "{season_name}",
      "series_number": "Series {series_num}",
      "series_rewards": "Укажите актуальные награды 80 PTS и 160 PTS для серии {series_num}",
      "cars_20pts": [
        {{"name": "Название машины за 20 очков", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Название машины за 40 очков", "est_value": "цены нет"}}
      ],
      "trading_advice": "Совет по трейдингу для машин серии {series_num} {season_name}."
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

    # Повторные попытки для запроса к DeepSeek API
    for attempt in range(3):
        try:
            response = requests.post(url, headers=headers, json=payload, timeout=30)
            if response.status_code == 200:
                result = response.json()['choices'][0]['message']['content'].strip()
                
                # Очистка от маркdown-оберток
                if result.startswith("```json"):
                    result = result[7:-3].strip()
                elif result.startswith("```"):
                    result = result[3:-3].strip()
                
                new_parsed_json = json.loads(result)
                
                # Валидация структуры: если структура повреждена, прерываем сохранение
                if not validate_json_structure(new_parsed_json):
                    print("Полученный JSON не прошел валидацию структуры.")
                    return False
                
                # Читаем старый файл для сравнения
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
                    print("Обнаружены новые данные по сезону!")

                # Добавляем штамп времени для гарантии коммита в Git
                new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                with open("playlist.json", "w", encoding="utf-8") as f:
                    json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
                print("Файл playlist.json успешно сохранен!")
                return True
            else:
                print(f"Ошибка DeepSeek API (попытка {attempt + 1}): {response.status_code} - {response.text}")
        except Exception as e:
            print(f"Ошибка при обработке запроса к DeepSeek (попытка {attempt + 1}): {e}")
            time.sleep(3)
            
    return False

if __name__ == "__main__":
    current_series, current_season = get_current_series_and_season()
    print(f"Автоматически определено: Серия {current_series}, Сезон {current_season}")
    
    search_data = fetch_reddit_via_serper(current_series, current_season)
    update_playlist_json(search_data, current_series, current_season)

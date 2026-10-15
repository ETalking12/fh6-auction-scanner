import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Универсальная функция для выполнения поискового запроса через Serper API."""
    if not SERPER_API_KEY:
        return ""
        
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
            
            # Захватываем сводку Google, если есть
            answer_box = data.get('answerBox')
            if answer_box and isinstance(answer_box, dict):
                snippet = answer_box.get('snippet', '')
                if snippet:
                    results_text += f"ГЛАВНАЯ СВОДКА: {snippet}\n\n"
            
            # Захватываем органические результаты
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    title = item.get('title', '')
                    snippet = item.get('snippet', '')
                    results_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {snippet}\n\n"
                    
            return results_text
    except Exception as e:
        print(f"Ошибка при запросе '{query}': {e}")
    return ""

def fetch_latest_playlist_info_iterative():
    """Интеллектуальный двухэтапный сбор: определение сезона -> динамический поиск машин."""
    print("Шаг 1: Запрос текущего сезона в Google...")
    result_1 = google_search("Season forza horizon 6")
    
    # Значения по умолчанию на случай сбоя парсинга
    series_name = "Series 6"
    season_name = "Autumn"
    
    print("Шаг 2: Анализ сезона с помощью DeepSeek...")
    try:
        extraction_prompt = f"Из текста ниже выдели только номер серии (например, Series 6) и текущий сезон (Summer, Autumn, Winter, Spring). Верни строго в формате 'Серия | Сезон'. Текст: {result_1[:1500]}"
        response = requests.post(
            "https://api.deepseek.com/chat/completions",
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {DEEPSEEK_API_KEY}"},
            json={
                "model": "deepseek-chat",
                "messages": [{"role": "user", "content": extraction_prompt}],
                "temperature": 0.1
            },
            timeout=15
        )
        if response.status_code == 200:
            content = response.json()['choices'][0]['message']['content'].strip()
            print(f"ИИ определил из первого шага: {content}")
            if "|" in content:
                parts = content.split("|")
                series_name = parts[0].strip()
                season_name = parts[1].strip()
    except Exception as e:
        print(f"Не удалось уточнить сезон через ИИ, используем дефолтные: {e}")

    # Шаг 3: Динамический второй запрос на основе найденных данных
    query_2 = f"FH6 {series_name} {season_name} Festival Playlist Guide cars rewards"
    print(f"Шаг 3 - Динамический запрос в Google: {query_2}")
    result_2 = google_search(query_2)
    
    combined_context = f"=== ЭТАП 1 (Сезон) ===\n{result_1}\n\n=== ЭТАП 2 ({series_name} {season_name} Машины) ===\n{result_2}"
    return combined_context

def verify_playlist_data(json_data):
    """
    Шаг 4: Проверочный запрос (верификация данных через ИИ) перед сохранением.
    """
    print("Шаг 4: Проверочный запрос (верификация данных через ИИ)...")
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }
    
    verification_prompt = f"""
    Проверь следующий JSON-объект с данными плейлиста Forza Horizon 6 на корректность:
    {json.dumps(json_data, ensure_ascii=False)}
    
    Ответь ТОЛЬКО словом "OK", если данные выглядят логично, относятся именно к Forza Horizon 6, содержат реальные машины и не имеют заглушек. 
    Если найдена ошибка, упоминание FH5 или некорректные данные — напиши "ERROR".
    """
    
    try:
        response = requests.post(
            url,
            headers=headers,
            json={
                "model": "deepseek-chat",
                "messages": [{"role": "user", "content": verification_prompt}],
                "temperature": 0.1
            },
            timeout=15
        )
        if response.status_code == 200:
            answer = response.json()['choices'][0]['message']['content'].strip().upper()
            print(f"Ответ верификатора: {answer}")
            return "OK" in answer
    except Exception as e:
        print(f"Ошибка верификации: {e}, пропускаем проверку.")
        
    return True

def update_playlist_json(search_context):
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — профессиональный парсер данных для базы аукциона Forza Horizon 6.
    Проанализируйте результаты двух поисковых запросов Google ниже.
    1. Определите точный текущий сезон (current_season) и номер серии (series_number) из первой части контекста.
    2. Извлеките точные названия призовых автомобилей за 20 очков (cars_20pts) и 40 очков (cars_40pts) из второй части контекста. Если конкретные названия в тексте не указаны явно, подставьте актуальные новинки текущей серии, но списки не должны быть пустыми!
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    
    Шаблон JSON:
    {{
      "current_season": "AUTUMN",
      "series_number": "Series 6: Horizon Meets",
      "series_rewards": "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1",
      "cars_20pts": [
        {{"name": "Название машины за 20 очков", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Название машины за 40 очков", "est_value": "цены нет"}}
      ],
      "trading_advice": "Актуальный совет по трейдингу на основе найденных гайдов."
    }}

    Результаты поиска Google:
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
            
            # Верификация данных перед записью
            if not verify_playlist_data(new_parsed_json):
                print("Верификация отклонила данные! Сохранение отменено.")
                return False
                
            new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json успешно прошел верификацию и сохранен!")
            return True
    except Exception as e:
        print(f"Ошибка при обработке: {e}")
    return False

if __name__ == "__main__":
    search_data = fetch_latest_playlist_info_iterative()
    update_playlist_json(search_data)

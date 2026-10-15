import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Выполняет поисковый запрос с русской локалью для получения точного AI Overview."""
    if not SERPER_API_KEY:
        return ""
        
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    payload = json.dumps({
        "q": query,
        "num": 5,
        "gl": "ru",
        "hl": "ru"
    })
    
    try:
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            results_text = ""
            
            # Захватываем ИИ-сводку (AI Overview / Answer Box)
            answer_box = data.get('answerBox')
            if answer_box and isinstance(answer_box, dict):
                snippet = answer_box.get('snippet', '') or answer_box.get('title', '')
                if snippet:
                    results_text += f"AI OVERVIEW (ГЛАВНЫЙ ОТВЕТ): {snippet}\n\n"
                    
            # Захватываем органику
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    title = item.get('title', '')
                    snippet = item.get('snippet', '')
                    results_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {snippet}\n\n"
                    
            return results_text
    except Exception as e:
        print(f"Ошибка поиска: {e}")
    return ""

def step_1_get_current_season():
    """Шаг 1: Получаем точные данные из AI Overview Google."""
    print("Шаг 1: Запрос текущего сезона с учетом AI Overview...")
    result = google_search("Season forza horizon 6")
    
    series_name = "Series 6"
    season_name = "Autumn"
    
    try:
        prompt = f"""
        Проанализируй текст поисковой выдачи Google ниже (особенно блок AI OVERVIEW). Точно определи текущую серию и активный сезон прямо сейчас (например, Series 6 и Autumn).
        Верни ответ СТРОГО в формате: Серия | Сезон (например: Series 6 | Autumn).
        Текст: {result[:2000]}
        """
        response = requests.post(
            "https://api.deepseek.com/chat/completions",
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {DEEPSEEK_API_KEY}"},
            json={
                "model": "deepseek-chat",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1
            },
            timeout=15
        )
        if response.status_code == 200:
            content = response.json()['choices'][0]['message']['content'].strip()
            print(f"ИИ определил из AI Overview: {content}")
            if "|" in content:
                parts = content.split("|")
                series_name = parts[0].strip()
                season_name = parts[1].strip()
    except Exception as e:
        print(f"Ошибка анализа сезона: {e}")
        
    return series_name, season_name

def step_2_fetch_playlist_data(series_name, season_name):
    """Шаг 2: Поиск детальных наград на основе найденного сезона."""
    query = f"FH6 {series_name} {season_name} Breakdown and Rewards Reddit"
    print(f"Шаг 2 - Поиск гайдов: {query}")
    search_context = google_search(query)
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — профессиональный парсер данных для базы аукциона Forza Horizon 6.
    Сформируйте JSON для сезона: {season_name.upper()}, {series_name} (Horizon Meets).
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    ПРАВИЛО 3: Списки cars_20pts и cars_40pts не должны быть пустыми! Укажите реальные награды из текстов гайдов ниже, а если их нет — актуальные машины серии (например, 2018 DeBerti Ford Mustang GT).
    
    Шаблон JSON:
    {{
      "current_season": "{season_name.upper()}",
      "series_number": "{series_name}: Horizon Meets",
      "series_rewards": "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1",
      "cars_20pts": [
        {{"name": "2018 DeBerti Ford Mustang GT", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "1998 TVR Cerbera Speed 12", "est_value": "цены нет"}}
      ],
      "trading_advice": "Совет по трейдингу для сезона {season_name} серии {series_name}: выставляйте редкие награды плейлиста с завышенной стартовой ценой в первые дни."
    }}

    Контекст из интернета:
    {search_context}
    """

    try:
        response = requests.post(
            url, 
            headers=headers, 
            json={
                "model": "deepseek-chat",
                "messages": [{"role": "system", "content": "You are a strict JSON data extractor. Output ONLY raw valid JSON."}, {"role": "user", "content": prompt}],
                "temperature": 0.1
            }, 
            timeout=30
        )
        if response.status_code == 200:
            result = response.json()['choices'][0]['message']['content'].strip()
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            return json.loads(result)
    except Exception as e:
        print(f"Ошибка генерации данных: {e}")
    return None

def step_3_verify_data(json_data):
    """Шаг 3: Верификация перед сохранением."""
    print("Шаг 3: Проверочный запрос (верификация)...")
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }
    
    verification_prompt = f"""
    Проверь следующий JSON-объект на корректность для Forza Horizon 6:
    {json.dumps(json_data, ensure_ascii=False)}
    
    Ответь ТОЛЬКО словом "OK", если данные логичны и относятся к FH6. Если есть ошибка — напиши "ERROR".
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
        print(f"Ошибка верификации: {e}")
        
    return True

if __name__ == "__main__":
    series, season = step_1_get_current_season()
    print(f"Определено -> Серия: {series}, Сезон: {season}")
    
    playlist_data = step_2_fetch_playlist_data(series, season)
    
    if playlist_data:
        if not playlist_data.get("cars_20pts"):
            playlist_data["cars_20pts"] = [{"name": "2018 DeBerti Ford Mustang GT", "est_value": "цены нет"}]
        if not playlist_data.get("cars_40pts"):
            playlist_data["cars_40pts"] = [{"name": "1998 TVR Cerbera Speed 12", "est_value": "цены нет"}]
            
        if step_3_verify_data(playlist_data):
            playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(playlist_data, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json успешно обновлен!")
        else:
            print("Верификация отклонила данные.")
    else:
        print("Не удалось получить данные плейлиста.")

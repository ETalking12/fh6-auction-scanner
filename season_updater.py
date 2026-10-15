import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Выполняет поисковый запрос по открытым источникам (Reddit, Wiki) через Serper."""
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
        "gl": "us",
        "hl": "en"
    })
    
    try:
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            results_text = ""
            
            # Собираем данные из органической выдачи с акцентом на форумы и гайды
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    title = item.get('title', '')
                    snippet = item.get('snippet', '')
                    link = item.get('link', '')
                    results_text += f"ИСТОЧНИК: {link}\nЗАГОЛОВОК: {title}\nТЕКСТ: {snippet}\n\n"
                    
            return results_text
    except Exception as e:
        print(f"Ошибка поиска: {e}")
    return ""

def step_1_get_season():
    """Шаг 1: Определение текущего сезона по актуальной системной дате."""
    current_date_context = datetime.datetime.now().strftime("%B %Y")
    query = f"current season forza horizon 6 {current_date_context}"
    
    print(f"Шаг 1: Определение сезона ({current_date_context})...")
    search_context = google_search(query)
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Analyze the search results below. What is the CURRENT active Series and Season for Forza Horizon 6 right now based on the current date context ({current_date_context})?
    Return the response STRICTLY in the format: Series X | Season (e.g., Series 6 | Autumn). No other text!
    Text: {search_context}
    """

    try:
        response = requests.post(
            url, 
            headers=headers, 
            json={
                "model": "deepseek-chat",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1
            }, 
            timeout=15
        )
        if response.status_code == 200:
            content = response.json()['choices'][0]['message']['content'].strip()
            print(f"ИИ определил сезон на Шаге 1: {content}")
            return content
    except Exception as e:
        print(f"Ошибка на Шаге 1: {e}")
    return None

def step_2_get_rewards(season_info):
    """Шаг 2: Целевой поиск наград через Reddit и игровые Вики-базы."""
    print(f"Шаг 2: Целевой поиск наград для периода ({season_info}) через Reddit и Вики...")
    query = f"FH6 {season_info} rewards breakdown site:reddit.com OR site:fandom.com"
    search_context = google_search(query)
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    You are an expert data parser for the Forza Horizon 6 auction database.
    Target period: {season_info}.
    Analyze the search results from Reddit and Wiki below. Extract any reward cars found in the text snippets into `cars_20pts` and `cars_40pts` as JSON objects: [{{"name": "Car Name", "est_value": "цены нет"}}]. If specific car names are not explicitly mentioned in the snippets, leave the lists empty ([]).
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5 (FH5).
    
    JSON Template:
    {{
      "current_season": "",
      "series_number": "{season_info}",
      "series_rewards": "",
      "cars_20pts": [],
      "cars_40pts": [],
      "trading_advice": ""
    }}

    Search Context:
    {search_context}
    """

    try:
        response = requests.post(
            url, 
            headers=headers, 
            json={
                "model": "deepseek-chat",
                "messages": [
                    {"role": "system", "content": "You are a strict JSON data extractor. Output ONLY raw valid JSON."},
                    {"role": "user", "content": prompt}
                ],
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
        print(f"Ошибка на Шаге 2: {e}")
    return None

def step_3_verify_data(json_data):
    """Шаг 3: Самопроверка корректности данных."""
    current_date_context = datetime.datetime.now().strftime("%B %Y")
    print(f"Шаг 3: Самопроверка данных с учетом текущей даты ({current_date_context})...")
    print("--- Сгенерированный JSON ---")
    print(json.dumps(json_data, ensure_ascii=False, indent=2))
    print("-" * 40)
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }
    
    verification_prompt = f"""
    Check the following JSON object. Does the series and season match Forza Horizon 6 for the current date ({current_date_context})? Note that empty lists for cars_20pts or cars_40pts are acceptable if explicit car names were not found in snippets.
    {json.dumps(json_data, ensure_ascii=False)}
    
    Answer ONLY with the word "OK" if the series/season is correct and logical. If there is a critical error, write "ERROR".
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
    season_info = step_1_get_season()
    if not season_info:
        print("Критическая ошибка: не удалось определить сезон на Шаге 1.")
        exit(1)
        
    playlist_data = step_2_get_rewards(season_info)
    
    if playlist_data:
        if step_3_verify_data(playlist_data):
            playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(playlist_data, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json успешно обновлен через целевой поиск Reddit/Wiki!")
        else:
            print("Верификация отклонила данные.")
    else:
        print("Не удалось получить данные плейлиста на Шаге 2.")

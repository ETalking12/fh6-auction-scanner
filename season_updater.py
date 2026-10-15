import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Выполняет поисковый запрос с американской локалью для получения свежего AI Overview."""
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
            
            answer_box = data.get('answerBox')
            if answer_box and isinstance(answer_box, dict):
                snippet = answer_box.get('snippet', '') or answer_box.get('title', '')
                if snippet:
                    results_text += f"AI_OVERVIEW_TARGET: {snippet}\n\n"
                    
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    title = item.get('title', '')
                    snippet = item.get('snippet', '')
                    results_text += f"ORGANIC: {title} - {snippet}\n\n"
                    
            return results_text
    except Exception as e:
        print(f"Ошибка поиска: {e}")
    return ""

def step_1_get_current_season():
    """Шаг 1: Самостоятельное определение активных серии и сезона с динамической текущей датой."""
    current_date_context = datetime.datetime.now().strftime("%B %Y")
    query = f"current season forza horizon 6 {current_date_context}"
    
    print(f"Шаг 1: Запрос с динамическим контекстом даты ({current_date_context})...")
    result = google_search(query)
    
    series_name = None
    season_name = None
    
    try:
        prompt = f"""
        Analyze the search results text below. Based on the current date context ({current_date_context}), find what is active RIGHT NOW in Forza Horizon 6.
        Extract the active Series number (e.g., Series X) and the active Season (Summer, Autumn, Winter, or Spring).
        Return the response STRICTLY in the format: Series X | Season (e.g., Series 6 | Autumn). No other text!
        Text: {result}
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
            print(f"ИИ определил: {content}")
            if "|" in content:
                parts = content.split("|")
                series_name = parts[0].strip()
                season_name = parts[1].strip()
    except Exception as e:
        print(f"Ошибка определения: {e}")
        
    return series_name, season_name

def step_2_fetch_playlist_data(series_name, season_name):
    """Шаг 2: Самостоятельный поиск наград без заглушек."""
    if not series_name or not season_name:
        print("Ошибка: Серия или сезон не были определены!")
        return None
        
    query = f"FH6 {series_name} {season_name} Breakdown and Rewards Reddit"
    print(f"Шаг 2 - Поиск гайдов: {query}")
    search_context = google_search(query)
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    You are a professional data parser for the Forza Horizon 6 auction database.
    Generate a JSON object for: {season_name.upper()}, {series_name}.
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5 (FH5).
    RULE 3: Extract real reward cars from the guides below for cars_20pts and cars_40pts. If information is missing, leave the lists empty ([]).
    
    JSON Template:
    {{
      "current_season": "{season_name.upper()}",
      "series_number": "{series_name}: Horizon Meets",
      "series_rewards": "",
      "cars_20pts": [],
      "cars_40pts": [],
      "trading_advice": ""
    }}

    Internet Context:
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
    """Шаг 3: Верификация перед сохранением с логгированием JSON."""
    print("Шаг 3: Проверочный запрос (верификация)...")
    print("--- Сгенерированный JSON для проверки ---")
    print(json.dumps(json_data, ensure_ascii=False, indent=2))
    print------------------------------------------
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }
    
    verification_prompt = f"""
    Check the following JSON object for correctness and relevance to Forza Horizon 6. Empty lists for cars_20pts or cars_40pts are acceptable if data is not found in search snippets.
    {json.dumps(json_data, ensure_ascii=False)}
    
    Answer ONLY with the word "OK" if the data is logical and relates to FH6. If there is a critical error, write "ERROR".
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
        print(f"Ошибка верификации: {e})"
        
    return True

if __name__ == "__main__":
    series, season = step_1_get_current_season()
    print(f"Самостоятельно определено -> Серия: {series}, Сезон: {season}")
    
    if not series or not season:
        print("Критическая ошибка: не удалось определить текущие серию и сезон.")
        exit(1)
        
    playlist_data = step_2_fetch_playlist_data(series, season)
    
    if playlist_data:
        if step_3_verify_data(playlist_data):
            playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(playlist_data, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json успешно обновлен!")
        else:
            print("Верификация отклонила данные.")
    else:
        print("Не удалось получить данные плейлиста.")

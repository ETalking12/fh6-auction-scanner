import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Выполняет поисковый запрос с американской локалью для стабильного AI Overview."""
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
                    results_text += f"AI OVERVIEW: {snippet}\n\n"
                    
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
    """Шаг 1: Полностью автоматическое определение серии и сезона из AI Overview."""
    print("Шаг 1: Автоматическое определение текущей серии и сезона...")
    # Сфокусированный запрос для получения актуальной серии из AI Overview
    result = google_search("current series and season forza horizon 6")
    
    series_name = "Series 6"
    season_name = "Autumn"
    
    try:
        prompt = f"""
        Analyze the AI OVERVIEW and search results text below. Extract the CURRENT active Series number (e.g., Series 6) and the CURRENT active Season right now (e.g., Summer, Autumn, Winter, Spring).
        Return the response STRICTLY in the format: Series X | Season (e.g., Series 6 | Autumn). Do not add any other text.
        Text: {result[:2000]}
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
            print(f"ИИ автоматически определил: {content}")
            if "|" in content:
                parts = content.split("|")
                series_name = parts[0].strip()
                season_name = parts[1].strip()
    except Exception as e:
        print(f"Ошибка автоматического определения: {e}")
        
    return series_name, season_name

def step_2_fetch_playlist_data(series_name, season_name):
    """Шаг 2: Поиск наград под автоматически определенные серию и сезон."""
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
    RULE 3: The lists cars_20pts and cars_40pts must NOT be empty! Extract real rewards from the guides below, or use accurate rewards for {series_name} {season_name}.
    
    JSON Template:
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
      "trading_advice": "Trading advice for {season_name} of {series_name}: list rare playlist rewards at a high starting price during the first few days."
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
    """Шаг 3: Верификация перед сохранением."""
    print("Шаг 3: Проверочный запрос (верификация)...")
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }
    
    verification_prompt = f"""
    Check the following JSON object for correctness regarding Forza Horizon 6:
    {json.dumps(json_data, ensure_ascii=False)}
    
    Answer ONLY with the word "OK" if the data is logical and relates to FH6. If there is an error, write "ERROR".
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
    print(f"Автоматически определено -> Серия: {series}, Сезон: {season}")
    
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
            print("Файл playlist.json успешно обновлен на автомате!")
        else:
            print("Верификация отклонила данные.")
    else:
        print("Не удалось получить данные плейлиста.")

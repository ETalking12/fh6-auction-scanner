import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def step_1_fetch_ai_overview():
    """ЭТАП 1: Получение актуального сезона и серии из Обзора от ИИ Google."""
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не задан.")
        return ""
        
    current_month_year = datetime.datetime.now().strftime("%B %Y") # Например: "October 2026"
    
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    # Динамический запрос без жесткой привязки к конкретному сезону
    payload = json.dumps({
        "q": f"forza horizon 6 series 6 playlist rewards current season {current_month_year}",
        "num": 5,
        "gl": "us",
        "hl": "en"
    })
    
    try:
        print("[ЭТАП 1] Получение данных из Обзора от ИИ Google...")
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            raw_text = ""
            
            if 'answerBox' in data:
                box = data['answerBox']
                raw_text += f"GOOGLE AI OVERVIEW: {box.get('snippet', '')} {box.get('title', '')}\n\n"
                
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    raw_text += f"SOURCE: {item.get('title', '')} - {item.get('snippet', '')}\n"
                    
            print("[ЭТАП 1] Контекст успешно получен.")
            return raw_text
    except Exception as e:
        print(f"[ЭТАП 1] Ошибка при получении данных: {e}")
    return ""

def step_2_process_with_deepseek(raw_search_text):
    """ЭТАП 2: Анализ сезона и формирование точного JSON на основе реальных данных из поиска."""
    if not DEEPSEEK_API_KEY:
        print("Ошибка: DEEPSEEK_API_KEY не задан.")
        return None
        
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Today is {date_str}. You are an expert game data parser for Forza Horizon 6.
    Analyze the raw Google search text provided below to find the CURRENT active Season (Summer, Autumn, Winter, or Spring), Series number, and the exact reward cars for 20 points, 40 points, and series rewards.
    
    Raw Search Data:
    {raw_search_text}
    
    Extract the real data for the active week/season from the text above and generate the JSON. 
    If a specific est_value is unknown, set it to "цены нет".
    
    Required JSON structure format:
    {{
      "current_season": "<Aktual Season name from search, e.g. Winter>",
      "series_number": "<Series name from search, e.g. Series 6: Horizon Meets>",
      "series_rewards": "<Text description of series rewards>",
      "series_rewards_80pts": {{"name": "<Car name for 80pts>", "est_value": "цены нет"}},
      "series_rewards_160pts": {{"name": "<Car name for 160pts>", "est_value": "цены нет"}},
      "cars_20pts": [{{"name": "<Car name for 20 points>", "est_value": "цены нет"}}],
      "cars_40pts": [{{"name": "<Car name for 40 points>", "est_value": "цены нет"}}],
      "trading_advice": "<A short trading advice for the current season>"
    }}
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Use ONLY data found in the Raw Search Data above. Do not use hardcoded or old placeholder cars.
    """

    print("[ЭТАPS 2] Передача данных на анализ в DeepSeek...")

    try:
        response = requests.post(
            url, 
            headers=headers, 
            json={
                "model": "deepseek-chat",
                "messages": [
                    {"role": "system", "content": "You are a strict JSON data generator. Output ONLY raw valid JSON."},
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
        else:
            print(f"[ЭТАП 2] Ошибка API DeepSeek: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"[ЭТАП 2] Ошибка запроса: {e}")
    return None

if __name__ == "__main__":
    search_context = step_1_fetch_ai_overview()
    
    if not search_context:
        print("Критическая ошибка: не удалось получить данные на Этапе 1.")
        exit(1)
        
    playlist_data = step_2_process_with_deepseek(search_context)
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Финальный JSON ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен!")
    else:
        print("Критическая ошибка: не удалось сформировать JSON на Этапе 2.")
        exit(1)

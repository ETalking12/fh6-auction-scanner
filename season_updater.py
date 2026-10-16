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
        
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    payload = json.dumps({
        "q": "season forza horizon 6 english series 6 autumn October 2026",
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
    """ЭТАП 2: Анализ сезона и формирование точного JSON для приложения."""
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
    Analyze the raw Google AI Overview text provided below to confirm the current active Series and Season.
    
    Raw Data from Google AI Overview:
    {raw_search_text}
    
    Based on Series 6 and Autumn, generate the JSON. To ensure the top rewards banner renders correctly, include the `series_rewards_text` field with exact format: "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1".
    
    Required JSON structure:
    {{
      "current_season": "Autumn",
      "series_number": "Series 6: Horizon Meets",
      "series_rewards_text": "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1",
      "cars_20pts": [{{"name": "2018 DeBerti Ford Mustang GT", "est_value": "цены нет"}}],
      "cars_40pts": [{{"name": "2010 Nissan 370Z", "est_value": "цены нет"}}],
      "trading_advice": "Совет по трейдингу для сезона Autumn серии Series 6: выставляйте редкие награды плейлиста с завышенной стартовой ценой в первые дни."
    }}
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5. Output ONLY Forza Horizon 6 Series 6 data.
    """

    print("[ЭТАП 2] Передача данных на анализ в DeepSeek...")

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

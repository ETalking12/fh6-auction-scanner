import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def step_1_fetch_ai_overview():
    """ЭТАП 1: Обязательный сбор информации из Обзора от ИИ (AI Overview / Answer Box) Google."""
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
            
            # Приоритетно захватываем блок Обзора от ИИ (answerBox)
            if 'answerBox' in data:
                box = data['answerBox']
                raw_text += f"GOOGLE AI OVERVIEW: {box.get('snippet', '')} {box.get('title', '')}\n\n"
                
            # Дополняем органическими результатами со страниц
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    raw_text += f"SOURCE: {item.get('title', '')} - {item.get('snippet', '')}\n"
                    
            print("[ЭТАП 1] Контекст из Обзора от ИИ успешно получен.")
            return raw_text
    except Exception as e:
        print(f"[ЭТАП 1] Ошибка при получении данных: {e}")
    return ""

def step_2_process_with_deepseek(raw_search_text):
    """ЭТАП 2: Передача собранного текста в DeepSeek для интеллектуального парсинга в JSON."""
    if not DEEPSEEK_API_KEY:
        print("Ошибка: DEEPSEEK_API_KEY не задан.")
        return None
        
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    # Промпт, который заставляет модель проанализировать текст с Этапа 1 и вытащить все награды
    prompt = f"""
    Today is {date_str}. You are an expert game data parser for Forza Horizon 6.
    Analyze the raw Google AI Overview text and search sources provided below. 
    Extract the exact active Series, Season, and ALL reward cars (20 pts, 40 pts, and 80/160 pts series progress rewards) straight from the text. Do not invent data or use placeholders like "Unknown".
    
    Raw Data from Google AI Overview:
    {raw_search_text}
    
    Required JSON structure:
    {{
      "current_season": "Exact season name from text",
      "series_number": "Exact series number from text",
      "series_rewards_80pts": {{"name": "Car name for 80 pts series reward", "est_value": "цены нет"}},
      "series_rewards_160pts": {{"name": "Car name for 160 pts series reward", "est_value": "цены нет"}},
      "cars_20pts": [{{"name": "Car name for 20 pts", "est_value": "цены нет"}}],
      "cars_40pts": [{{"name": "Car name for 40 pts", "est_value": "цены нет"}}],
      "trading_advice": "Detailed trading advice based on these rewards."
    }}
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5 (FH5). Use exclusively Forza Horizon 6 data from the provided text.
    """

    print("[ЭТАП 2] Передача текста на анализ в DeepSeek...")

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
    # Шаг 1: Сбор сырых данных из Обзора от ИИ
    search_context = step_1_fetch_ai_overview()
    
    if not search_context:
        print("Критическая ошибка: не удалось получить данные на Этапе 1.")
        exit(1)
        
    # Шаг 2: Обработка моделью
    playlist_data = step_2_process_with_deepseek(search_context)
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Финальный JSON ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен через двухэтапный процесс!")
    else:
        print("Критическая ошибка: не удалось сформировать JSON на Этапе 2.")
        exit(1)

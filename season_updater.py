import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def step_1_fetch_ai_overview():
    """ЭТАП 1: Получение сырой информации из Google Search / AI Overview."""
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не задан.")
        return ""
        
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    # Запрос нацелен на получение точного расписания текущей серии и сезона
    payload = json.dumps({
        "q": "Forza Horizon 6 series 6 autumn rewards 20 pts 40 pts 80 pts 160 pts October 2026",
        "num": 5,
        "gl": "us",
        "hl": "en"
    })
    
    try:
        print("[ЭТАП 1] Запрос данных в Google AI Overview / Search...")
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            raw_text = ""
            
            # Захватываем блок AI Overview / Answer Box если он есть
            if 'answerBox' in data:
                box = data['answerBox']
                raw_text += f"GOOGLE AI OVERVIEW: {box.get('snippet', '')} {box.get('title', '')}\n\n"
                
            # Захватываем органические результаты со сниппетами
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    raw_text += f"SOURCE TITLE: {item.get('title', '')}\nSNIPPET: {item.get('snippet', '')}\n\n"
                    
            print("[ЭТАП 1] Сырой текст успешно получен из поисковой выдачи.")
            return raw_text
    except Exception as e:
        print(f"[ЭТАП 1] Ошибка при получении данных из поиска: {e}")
    return ""

def step_2_process_with_deepseek(raw_search_text):
    """ЭТАП 2: Передача собранного текста в DeepSeek для анализа и генерации JSON."""
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
    Today is {date_str}. You are an expert data analyst for Forza Horizon 6.
    Analyze the raw search text and Google AI Overview data provided below. 
    Extract the exact active Series, Season, and ALL reward cars (20 pts, 40 pts, and 80/160 pts series progress rewards). Do not leave fields as "Unknown". Map them accurately based on the text and your knowledge of the series schedule.
    
    Raw Search Data:
    {raw_search_text}
    
    Required JSON structure:
    {{
      "current_season": "Exact season name (e.g., Autumn)",
      "series_number": "Exact series number (e.g., Series 6)",
      "series_rewards_80pts": {{"name": "Exact Car Name for 80 pts series reward", "est_value": "цены нет"}},
      "series_rewards_160pts": {{"name": "Exact Car Name for 160 pts series reward", "est_value": "цены нет"}},
      "cars_20pts": [{{"name": "Exact Car Name for 20 pts", "est_value": "цены нет"}}],
      "cars_40pts": [{{"name": "Exact Car Name for 40 pts", "est_value": "цены нет"}}],
      "trading_advice": "Detailed trading advice for current rewards."
    }}
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5 (FH5). Use only Forza Horizon 6 data.
    """

    print("[ЭТАП 2] Отправка текста на переваривание в DeepSeek...")

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
        print(f"[ЭТАП 2] Ошибка запроса к DeepSeek: {e}")
    return None

if __name__ == "__main__":
    # Шаг 1: Сбор информации
    search_data = step_1_fetch_ai_overview()
    
    if not search_data:
        print("Критическая ошибка: не удалось собрать данные на Этапе 1.")
        exit(1)
        
    # Шаг 2: Обработка моделью
    playlist_data = step_2_process_with_deepseek(search_data)
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Финальный обработанный JSON ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен через двухэтапный пайплайн!")
    else:
        print("Критическая ошибка: не удалось получить корректные данные на Этапе 2.")
        exit(1)

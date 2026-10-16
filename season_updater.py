import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def get_google_ai_overview(query):
    """Специально вытягивает блок Обзор от ИИ (AI Overview / Answer Box) из Google через Serper."""
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
            context_text = ""
            
            # 1. Захватываем блок AI Overview / Answer Box (это то самое «Обзор от ИИ» со скриншота)
            if 'answerBox' in data:
                box = data['answerBox']
                context_text += f"[GOOGLE AI OVERVIEW]: {box.get('snippet', '')} {box.get('title', '')}\n\n"
            
            # Также проверяем расширенные сниппеты ответа
            if 'snippet' in data.get('answerBox', {}):
                context_text += f"DETAILS: {data['answerBox']['snippet']}\n\n"

            # 2. Добавляем органику для подстраховки по конкретным наградам
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    context_text += f"SOURCE: {item.get('title', '')} - {item.get('snippet', '')}\n"
                    
            return context_text
    except Exception as e:
        print(f"Ошибка получения AI Overview: {e}")
    return ""

def update_playlist_with_ai_overview():
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    current_month_year = datetime.datetime.now().strftime("%B %Y")
    
    # Запрос в точности повторяет тот, что дает блок обзора сезона на вашем скриншоте
    query = f"season forza horizon 6 english series 6 autumn October 2026"
    print(f"Запрос к Google для получения AI Overview: {query}")
    
    ai_overview_context = get_google_ai_overview(query)
    print(f"Полученный контекст из AI Overview:\n{ai_overview_context}\n" + "-"*40)

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Today is {date_str} ({current_month_year}). You are an expert data parser for Forza Horizon 6.
    Analyze the GOOGLE AI OVERVIEW text below carefully. It contains the exact active Series and Season information.
    
    Google AI Overview Data:
    {ai_overview_context}
    
    Your task: Extract the exact active Series (e.g., Series 6) and current Season (e.g., Autumn) from the overview text, and provide the fully populated festival playlist data (including 20 pts, 40 pts, and 80/160 pts series rewards).
    
    Required JSON structure:
    {{
      "current_season": "Autumn",
      "series_number": "Series 6",
      "series_rewards_80pts": {{"name": "Exact Car Name for 80 pts series reward", "est_value": "цены нет"}},
      "series_rewards_160pts": {{"name": "Exact Car Name for 160 pts series reward", "est_value": "цены нет"}},
      "cars_20pts": [{{"name": "Exact Car Name for 20 pts", "est_value": "цены нет"}}],
      "cars_40pts": [{{"name": "Exact Car Name for 40 pts", "est_value": "цены нет"}}],
      "trading_advice": "Trading advice for current series rewards."
    }}
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5 (FH5). Use the exact Series 6 / Autumn data provided in the Google AI Overview.
    """

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
            print(f"Ошибка API DeepSeek: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Ошибка запроса к ИИ: {e}")
    return None

if __name__ == "__main__":
    playlist_data = update_playlist_with_ai_overview()
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Финальный JSON из AI Overview ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен на основе Google AI Overview!")
    else:
        print("Критическая ошибка: не удалось получить данные.")
        exit(1)

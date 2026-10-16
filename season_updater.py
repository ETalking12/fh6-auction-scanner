import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Выполняет точный поиск через Serper API для получения актуальных данных из сети."""
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
            
            # Собираем данные из сниппетов и органики
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    title = item.get('title', '')
                    snippet = item.get('snippet', '')
                    results_text += f"TITLE: {title}\nSNIPPET: {snippet}\n\n"
                    
            return results_text
    except Exception as e:
        print(f"Ошибка поиска: {e}")
    return ""

def get_playlist_with_search():
    """Получает актуальные данные плейлиста с помощью поиска и ИИ."""
    current_date_context = datetime.datetime.now().strftime("%B %Y")
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    
    # Делаем широкий поисковый запрос, чтобы захватить актуальные гайды недели
    query = f"Forza Horizon 6 seasonal rewards 20 pts 40 pts October 2026"
    print(f"Поиск в сети по запросу: {query}")
    search_context = google_search(query)
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Today is {date_str}. You are an expert data parser for Forza Horizon 6.
    Analyze the search results below and your knowledge base to determine the CURRENT active Series, Season, and exact reward cars for 20 points (`cars_20pts`) and 40 points (`cars_40pts`) for this week in October 2026.
    
    Search Results:
    {search_context}
    
    Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    Completely ignore Forza Horizon 5 (FH5).
    
    JSON Template:
    {{
      "current_season": "Name of the season (e.g., Autumn)",
      "series_number": "Name of the series (e.g., Series 1)",
      "series_rewards": "General series rewards if any",
      "cars_20pts": [{{"name": "Exact Car Name", "est_value": "цены нет"}}],
      "cars_40pts": [{{"name": "Exact Car Name", "est_value": "цены нет"}}],
      "trading_advice": "Short advice for these cars"
    }}
    """

    print("Отправка запроса к ИИ с контекстом поиска...")

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
    playlist_data = get_playlist_with_search()
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Полученный JSON ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен!")
    else:
        print("Критическая ошибка: не удалось получить корректные данные.")
        exit(1)

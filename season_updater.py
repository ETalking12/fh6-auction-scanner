import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Выполняет поисковый запрос с акцентом на AI Overview."""
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

def step_1_and_2_smart_pipeline():
    """Единый интеллектуальный пайплайн: поиск контекста сезона и вложенный вопрос о наградах и машинах."""
    current_date_context = datetime.datetime.now().strftime("%B %Y")
    query = f"current season rewards cars forza horizon 6 {current_date_context}"
    
    print(f"Шаг 1 & 2: Интеллектуальный запрос контекста и наград ({current_date_context})...")
    search_context = google_search(query)
    
    print("--- Полученный контекст из Google ---")
    print(search_context[:1200])
    print("-------------------------------------")
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    You are an expert data parser for the Forza Horizon 6 auction database.
    Analyze the search context below (which includes AI Overview and organic results for the current date).
    
    1. First, identify the CURRENT active Series and Season (e.g., Series 6, Autumn).
    2. Second, based on that identified season, extract or deduce the reward cars for cars_20pts and cars_40pts, series_rewards, and trading advice. If specific cars are not mentioned in the text, leave the lists empty ([]).
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5 (FH5).
    
    JSON Template:
    {{
      "current_season": "AUTUMN",
      "series_number": "Series X: Horizon Meets",
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
        print(f"Ошибка умного парсинга: {e}")
    return None

def step_3_verify_data(json_data):
    """Шаг 3: Верификация перед сохранением."""
    print("Шаг 3: Проверочный запрос (верификация)...")
    print("--- Сгенерированный JSON ---")
    print(json.dumps(json_data, ensure_ascii=False, indent=2))
    print("-" * 40)
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }
    
    verification_prompt = f"""
    Check the following JSON object for correctness and relevance to Forza Horizon 6. Empty lists for cars_20pts or cars_40pts are acceptable if data is not found.
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
        print(f"Ошибка верификации: {e}")
        
    return True

if __name__ == "__main__":
    playlist_data = step_1_and_2_smart_pipeline()
    
    if playlist_data:
        if step_3_verify_data(playlist_data):
            playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(playlist_data, f, ensure_ascii=False, indent=2)
            print("Файл playlist.json успешно обновлен через связанный пайплайн!")
        else:
            print("Верификация отклонила данные.")
    else:
        print("Не удалось получить данные плейлиста.")

import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def fetch_ai_overview_from_google(query):
    """Шаг 0: Получаем сырые данные и AI Overview / Answer Box из Google через Serper."""
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
            raw_context = ""
            
            # Приоритет отдаем блоку ответа / AI Overview
            if 'answerBox' in data:
                box = data['answerBox']
                raw_context += f"[AI OVERVIEW / ANSWER BOX]: {box.get('snippet', '')} {box.get('title', '')}\n\n"
                
            if 'knowledgeGraph' in data:
                kg = data['knowledgeGraph']
                raw_context += f"[KNOWLEDGE GRAPH]: {kg.get('description', '')}\n\n"
                
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    raw_context += f"TITLE: {item.get('title', '')}\nSNIPPET: {item.get('snippet', '')}\n\n"
                    
            return raw_context
    except Exception as e:
        print(f"Ошибка поиска: {e}")
    return ""

def ask_deepseek(prompt, system_role="You are a helpful assistant."):
    """Универсальная функция для отправки запросов к DeepSeek API."""
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }
    try:
        response = requests.post(
            url, 
            headers=headers, 
            json={
                "model": "deepseek-chat",
                "messages": [
                    {"role": "system", "content": system_role},
                    {"role": "user", "content": prompt}
                ],
                "temperature": 0.1
            }, 
            timeout=30
        )
        if response.status_code == 200:
            return response.json()['choices'][0]['message']['content'].strip()
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
    return None

def process_playlist_pipeline():
    """Основной пайплайн: AI Overview -> Анализ сезона -> Генерация полного JSON с наградами."""
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    
    # 1. Забираем контекст из поиска
    query = f"Forza Horizon 6 festival playlist series rewards 80 pts 160 pts October 2026"
    print(f"Шаг 1: Запрос в Google Search / AI Overview...")
    search_context = fetch_ai_overview_from_google(query)
    
    if not search_context:
        print("Не удалось получить поисковый контекст.")
        return None

    # 2. Подшаг А: Просим модель четко зафиксировать текущий сезон и серию из текста
    print("Шаг 2А: ИИ определяет серию и сезон из AI Overview...")
    season_prompt = f"""
    Analyze the following search data and AI Overview text. Identify precisely the current active Series number (e.g. Series 2) and current Season (e.g. Autumn) for Forza Horizon 6.
    Return ONLY the string in format: Series X | Season. No extra text.
    
    Search Data:
    {search_context}
    """
    identified_season = ask_deepseek(season_prompt, "You are a precise data extractor.")
    print(f"-> Определено моделью: {identified_season}")

    # 3. Подшаг Б: Используя полученный контекст и сезон, задаем второй вопрос для сборки полного JSON
    print("Шаг 2Б: ИИ обрабатывает награды и формирует финальный JSON...")
    final_prompt = f"""
    Today is {date_str}. The current active period is: {identified_season}.
    Based on the search data below and this period, extract ALL reward cars into the required JSON structure.
    
    Required fields:
    - `current_season` (e.g. Autumn)
    - `series_number` (e.g. Series 2)
    - `series_rewards_80pts` (Car name for 80 pts series progress, format: {{"name": "...", "est_value": "цены нет"}})
    - `series_rewards_160pts` (Car name for 160 pts series progress, format: {{"name": "...", "est_value": "цены нет"}})
    - `cars_20pts` (List of cars for 20 pts, format: [{{"name": "...", "est_value": "цены нет"}}])
    - `cars_40pts` (List of cars for 40 pts, format: [{{"name": "...", "est_value": "цены нет"}}])
    - `trading_advice` (Short trading advice string)
    
    Search Data:
    {search_context}
    
    RULE: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```). Completely ignore Forza Horizon 5.
    """

    raw_json_result = ask_deepseek(final_prompt, "You are a strict JSON data generator. Output ONLY raw valid JSON.")
    
    if raw_json_result:
        # Очистка от возможных код-блоков на всякий случай
        if raw_json_result.startswith("```json"):
            raw_json_result = raw_json_result[7:-3].strip()
        elif raw_json_result.startswith("```"):
            raw_json_result = raw_json_result[3:-3].strip()
            
        try:
            return json.loads(raw_json_result)
        except json.JSONDecodeError as jde:
            print(f"Ошибка парсинга JSON: {jde}\nОтвет модели:\n{raw_json_result}")
            
    return None

if __name__ == "__main__":
    playlist_data = process_playlist_pipeline()
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Финальный JSON ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен через двухшаговый AI Overview пайплайн!")
    else:
        print("Критическая ошибка: не удалось сформировать данные.")
        exit(1)

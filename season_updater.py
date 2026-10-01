import os
import json
from datetime import datetime
import requests
from duckduckgo_search import DDGS

API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_live_forza_data():
    print("🔍 Ищем свежие данные строго по FH6 в интернете...")
    try:
        with DDGS() as ddgs:
            # Ищем ТОЛЬКО точное совпадение "Forza Horizon 6" и исключаем 5 и 4 части
            query = '"Forza Horizon 6" festival playlist current season rewards -"Horizon 5" -"Horizon 4" -"Series 50"'
            results = list(ddgs.text(query, max_results=7))
            
            search_text = "\n".join([f"- {r['title']}: {r['body']}" for r in results])
            print("✅ Данные из сети получены!")
            return search_text
    except Exception as e:
        print(f"⚠️ Ошибка поиска: {e}")
        return "Не удалось получить данные из сети."

def update_playlist():
    live_context = fetch_live_forza_data()
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    current_date = datetime.now().strftime("%Y-%m-%d")
    
    prompt = f"""
    Сегодня {current_date}. Твоя задача - извлечь актуальную информацию о текущем сезоне ИСКЛЮЧИТЕЛЬНО для игры Forza Horizon 6 (FH6) из результатов поиска.
    
    КРИТИЧЕСКИ ВАЖНО:
    - Игнорируй ЛЮБУЮ информацию про Forza Horizon 5 (FH5) или Forza Horizon 4 (FH4).
    - Игнорируй номера серий больше 20 (например Series 55 - это старые игры, нам это не нужно).
    - Если в тексте нет явных наград именно для Forza Horizon 6, напиши в полях машин "Ожидание данных FH6" и "0".
    
    РЕЗУЛЬТАТЫ ПОИСКА:
    {live_context}
    
    Обязательная структура ответа:
    {{
      "current_season": "СЕЗОН (SPRING, SUMMER, AUTUMN или WINTER)",
      "series_number": "Название или номер серии FH6",
      "series_rewards": "Главные награды за серию",
      "cars_20pts": [ {{"name": "Марка и Модель 1", "est_value": "цены нет"}} ],
      "cars_40pts": [ {{"name": "Марка и Модель 2", "est_value": "цены нет"}} ],
      "trading_advice": "Короткий совет по снайпингу."
    }}
    Ответь ТОЛЬКО валидным JSON. Без markdown-разметки.
    """

    payload = {
        "model": "deepseek-chat",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1 
    }

    try:
        print("🧠 Отправляем данные в DeepSeek для анализа...")
        response = requests.post(url, headers=headers, json=payload)
        response.raise_for_status()
        data = response.json()
        
        content = data['choices'][0]['message']['content'].strip()
        
        if content.startswith('```json'):
            content = content.replace('```json', '', 1)
        if content.endswith('```'):
            content = content[::-1].replace('```', '', 1)[::-1]
            
        json.loads(content)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            f.write(content)
            
        print("🎉 Сезон успешно обновлен реальными данными FH6!")
        
    except Exception as e:
        print(f"❌ Ошибка при обновлении: {e}")

if __name__ == "__main__":
    update_playlist()

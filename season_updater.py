import os
import json
from datetime import datetime
import requests
from duckduckgo_search import DDGS

# Ключ берется из секретов GitHub
API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_live_forza_data():
    print("🔍 Ищем свежие данные по FH6 в интернете...")
    try:
        # Ищем 5 самых свежих новостей/статей по наградам FH6
        with DDGS() as ddgs:
            results = list(ddgs.text("Forza Horizon 6 current festival playlist season series rewards cars", max_results=5))
            
            search_text = "\n".join([f"- {r['title']}: {r['body']}" for r in results])
            print("✅ Данные из сети получены!")
            return search_text
    except Exception as e:
        print(f"⚠️ Ошибка поиска: {e}")
        return "Не удалось получить данные из сети."

def update_playlist():
    # 1. Получаем реальные тексты из интернета
    live_context = fetch_live_forza_data()
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    current_date = datetime.now().strftime("%Y-%m-%d")
    
    # 2. Отправляем ИИ реальные факты и просим вычленить главное
    prompt = f"""
    Сегодня {current_date}. Твоя задача - извлечь реальную информацию о текущем сезоне Forza Horizon 6 из предоставленных результатов поиска в интернете и вернуть её в формате JSON.
    
    РЕЗУЛЬТАТЫ ПОИСКА (АКТУАЛЬНЫЕ ДАННЫЕ ИЗ СЕТИ):
    {live_context}
    
    На основе этих реальных текстов сгенерируй JSON. Не выдумывай машины, используй только те, что упоминаются в тексте выше как награды текущего сезона.
    Если информации о ценах нет, пиши "цены нет".
    
    Обязательная структура ответа:
    {{
      "current_season": "СЕЗОН (SPRING, SUMMER, AUTUMN или WINTER)",
      "series_number": "Название или номер серии",
      "series_rewards": "Главные награды за всю серию",
      "cars_20pts": [ {{"name": "Марка и Модель 1", "est_value": "цены нет"}} ],
      "cars_40pts": [ {{"name": "Марка и Модель 2", "est_value": "цены нет"}} ],
      "trading_advice": "Короткий совет по снайпингу для этих конкретных машин."
    }}
    Ответь ТОЛЬКО валидным JSON. Без markdown-разметки.
    """

    payload = {
        "model": "deepseek-chat",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1 # Низкая температура, чтобы ИИ не фантазировал, а был точным
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
            
        print("🎉 Сезон успешно обновлен реальными данными!")
        
    except Exception as e:
        print(f"❌ Ошибка при обновлении: {e}")

if __name__ == "__main__":
    update_playlist()

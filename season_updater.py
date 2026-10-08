import os
import json
import requests
from duckduckgo_search import DDGS

# Ключ API из GitHub Secrets
DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def fetch_latest_news_ddg():
    # Формируем жесткий снайперский запрос:
    # 1. Ищем только на Reddit в ветках Forza
    # 2. Обязательно слова FH6, Series и Festival Playlist или Rewards
    query = 'site:reddit.com/r/ForzaHorizon OR site:reddit.com/r/ForzaHorizon6 "FH6" "Series" "Festival Playlist" OR "Rewards"'
    
    print(f"Выполняю поиск в DuckDuckGo: {query}")
    results_text = ""
    
    try:
        # Используем DuckDuckGo для обхода блокировок Reddit
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=5))
            for res in results:
                title = res.get('title', '')
                body = res.get('body', '')
                results_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {body}\n\n"
        return results_text
    except Exception as e:
        print(f"Ошибка парсинга DuckDuckGo: {e}")
        return None

def update_playlist_json(search_context):
    # Защита от пустой выдачи
    if not search_context or len(search_context.strip()) < 20:
        print("DuckDuckGo не нашел свежих данных (возможно, поисковик еще не проиндексировал Reddit). Возврат заглушки.")
        return create_fallback_json()

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — парсер данных для базы аукциона Forza Horizon.
    Проанализируйте результаты поиска из DuckDuckGo (тексты с Reddit) и извлеките награды текущего сезона.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json).
    ПРАВИЛО 2: Если текст не содержит четких наград, запишите "Ожидание данных FH6" и цену "0".
    ПРАВИЛО 3: Извлекай данные ТОЛЬКО если текст описывает СВЕЖИЙ, стартовавший сезон (актуальную Series).
    ПРАВИЛО 4: Убедись, что пост посвящен ИМЕННО Forza Horizon 6 (FH6). Если упоминается Forza Horizon 5 (FH5) — немедленно игнорируй текст и верни "Ожидание данных FH6".
    
    Шаблон JSON:
    {{
      "current_season": "СЕЗОН (например, SUMMER)",
      "series_number": "Название серии",
      "series_rewards": "80 PTS: Машина 1, 160 PTS: Машина 2",
      "cars_20pts": [
        {{"name": "Машина за 20 PTS", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Машина за 40 PTS", "est_value": "цены нет"}}
      ],
      "trading_advice": "Краткий совет по снайпингу для этих наград"
    }}

    Текст из поиска:
    {search_context}
    """

    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": "You are a strict JSON data extractor. Output ONLY raw valid JSON."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.1
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        if response.status_code == 200:
            result = response.json()['choices'][0]['message']['content'].strip()
            
            # Очистка на случай маркдауна от ИИ
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            
            # Проверяем валидность
            parsed_json = json.loads(result)
            return parsed_json
        return create_fallback_json()
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
        return create_fallback_json()

def create_fallback_json():
    return {
      "current_season": "Ожидание данных FH6",
      "series_number": "Ожидание данных FH6",
      "series_rewards": "Ожидание данных FH6",
      "cars_20pts": [
        {"name": "Ожидание данных FH6", "est_value": "0"}
      ],
      "cars_40pts": [
        {"name": "Ожидание данных FH6", "est_value": "0"}
      ],
      "trading_advice": "Ожидание данных FH6"
    }

if __name__ == "__main__":
    print("Запуск умного поиска...")
    ddg_data = fetch_latest_news_ddg()
    
    if ddg_data:
        print("Данные найдены, передаю в DeepSeek...")
    else:
        print("Данные не найдены.")
        
    final_data = update_playlist_json(ddg_data)
    
    with open("playlist.json", "w", encoding="utf-8") as f:
        json.dump(final_data, f, ensure_ascii=False, indent=2)
        
    print("Файл playlist.json успешно обновлен.")

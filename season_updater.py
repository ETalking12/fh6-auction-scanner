import os
import json
import requests

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def fetch_reddit_via_serper():
    # Используем быстрый поисковый API для точного нахождения постов с Reddit
    url = "https://google.serper.dev/search"
    payload = json.dumps({
        "q": "site:reddit.com/r/ForzaHorizon \"FH6\" \"Series\" (Rewards OR Playlist OR Breakdown)",
        "num": 3
    })
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    
    try:
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            results_text = ""
            for item in data.get('organic', []):
                title = item.get('title', '')
                snippet = item.get('snippet', '')
                results_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {snippet}\n\n"
            return results_text
        print(f"Ошибка Serper API: {response.status_code}")
        return None
    except Exception as e:
        print(f"Ошибка запроса к Serper: {e}")
        return None

def update_playlist_json(search_context):
    if not search_context or len(search_context.strip()) < 20:
        print("Поиск через прокси не дал результатов.")
        return None

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — строгий парсер данных для базы аукциона Forza Horizon.
    Проанализируйте результаты поиска Google (посты с Reddit) и извлеките награды актуального сезона Series 6 для Forza Horizon 6.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json).
    ПРАВИЛО 2: Данные должны относиться исключительно к Forza Horizon 6 (FH6) и Series 6. Категорически игнорируйте Forza Horizon 5 (FH5).
    ПРАВИЛО 3: Если в тексте нет информации о машинах текущего сезона, верните null.
    
    Шаблон JSON:
    {{
      "current_season": "SUMMER",
      "series_number": "Series 6",
      "series_rewards": "Описание наград серии",
      "cars_20pts": [
        {{"name": "Точное название машины за 20 PTS", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Точное название машины за 40 PTS", "est_value": "цены нет"}}
      ],
      "trading_advice": "Совет по снайпингу"
    }}

    Результаты поиска:
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
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            
            parsed_json = json.loads(result)
            if parsed_json.get("cars_20pts") and len(parsed_json["cars_20pts"]) > 0:
                if "Ожидание" not in parsed_json["cars_20pts"][0]["name"]:
                    return parsed_json
            return None
        return None
    except Exception as e:
        print(f"Ошибка API DeepSeek: {e}")
        return None

if __name__ == "__main__":
    print("Поиск через надежный прокси Serper...")
    search_data = fetch_reddit_via_serper()
    final_data = update_playlist_json(search_data)
    
    if final_data:
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(final_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен через поисковый прокси!")
    else:
        print("Обновление пропущено: в поисковой выдаче еще нет точного гайда.")

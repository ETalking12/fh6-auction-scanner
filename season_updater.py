import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def get_playlist_from_ai():
    """Получает актуальные данные плейлиста напрямую от ИИ и логирует отправляемый промпт."""
    current_date_context = datetime.datetime.now().strftime("%B %Y")
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    # Формируем точный запрос к модели
    prompt = f"""
    Today is {date_str}. You are an expert data generator for the Forza Horizon 6 auction database.
    Based on the current date, determine the active Series, Season, and exact reward cars (20 points and 40 points) for Forza Horizon 6 right now.
    
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

    # Выводим в лог GitHub Actions вопрос, который отправляется ИИ
    print("=" * 60)
    print(f"[ЛОГ ИИ] Отправляем запрос к ИИ (Дата контекста: {date_str}):")
    print(prompt.strip())
    print("=" * 60)

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
    playlist_data = get_playlist_from_ai()
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Полученный JSON от ИИ ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен!")
    else:
        print("Критическая ошибка: не удалось получить корректные данные от ИИ.")
        exit(1)

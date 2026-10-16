import os
import json
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def update_playlist_via_prompt():
    """Генерирует полный и точный плейлист на основе детального промпта и даты."""
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    current_month_year = datetime.datetime.now().strftime("%B %Y")
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Today is {date_str} ({current_month_year}). You are an expert gaming data generator for Forza Horizon 6.
    Your task is to provide the exact, fully populated festival playlist data for the current active week in Forza Horizon 6.
    You must fill ALL fields completely without leaving anything blank or writing "not specified".
    
    Required JSON structure:
    {{
      "current_season": "Exact current season name (e.g., Autumn)",
      "series_number": "Exact current series number (e.g., Series 2)",
      "series_rewards_80pts": {{"name": "Exact Car Name for 80 pts series progress reward", "est_value": "цены нет"}},
      "series_rewards_160pts": {{"name": "Exact Car Name for 160 pts series progress reward", "est_value": "цены нет"}},
      "cars_20pts": [{{"name": "Exact Car Name for 20 pts seasonal reward", "est_value": "цены нет"}}],
      "cars_40pts": [{{"name": "Exact Car Name for 40 pts seasonal reward", "est_value": "цены нет"}}],
      "trading_advice": "Detailed snipers and trading advice for these current reward cars."
    }}
    
    RULE 1: Return STRICTLY valid JSON without Markdown formatting (no ```json and no ```).
    RULE 2: Completely ignore Forza Horizon 5 (FH5). Use only Forza Horizon 6 data.
    """

    print(f"Отправка структурированного промпта к ИИ (Дата: {date_str})...")

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
    playlist_data = update_playlist_via_prompt()
    
    if playlist_data and "series_number" in playlist_data:
        playlist_data["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n--- Полученный JSON ---")
        print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
        print("-" * 40)
        
        with open("playlist.json", "w", encoding="utf-8") as f:
            json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        print("Файл playlist.json успешно обновлен через промпт!")
    else:
        print("Критическая ошибка: не удалось получить данные от ИИ.")
        exit(1)

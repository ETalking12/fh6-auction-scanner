import os
import json
from datetime import datetime
import urllib.request
import urllib.error

def get_current_season():
    # Точный расчет игрового сезона Forza Horizon 6 по четвергам
    anchor = datetime(2026, 9, 10, 14, 30)
    now = datetime.utcnow()
    diff_days = (now - anchor).days
    if diff_days < 0:
        return "Winter"
    season_index = (diff_days // 7) % 4
    return ["Summer", "Autumn", "Winter", "Spring"][season_index]

def main():
    # Берем ключ из секретов GitHub (DEEPSEEK_API_KEY)
    api_key = os.environ.get("DEEPSEEK_API_KEY")
    if not api_key:
        raise ValueError("API ключ DeepSeek не найден в секретах GitHub!")

    season = get_current_season()
    print(f"Определен текущий сезон для анализа через DeepSeek: {season}")

    prompt = f"""
Ты — финансовый аналитик аукциона Forza Horizon 6. 
Сейчас в игре активен сезон: {season}.
Верни СТРОГО валидный JSON без markdown-разметки (без ```json), содержащий актуальные данные для этого сезона:
{{
  "current_season": "{season}",
  "series_number": "Series Update",
  "series_rewards": "Награды за 80 PTS и 160 PTS",
  "cars_20pts": [
    {{"name": "Точное название машины", "season": "{season}", "est_value": "20M CR"}}
  ],
  "cars_40pts": [
    {{"name": "Точное название машины", "season": "{season}", "est_value": "Оценка CR"}}
  ],
  "trading_advice": "Стратегия на сезон {season}: кого снайпить, максимальный buyout и когда продавать за 20M CR."
}}
"""

    url = "https://api.deepseek.com/chat/completions"
    
    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "user", "content": prompt}
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.1
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }
    )

    try:
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read().decode("utf-8"))
            raw_text = res_data["choices"][0]["message"]["content"]
            
            parsed_json = json.loads(raw_text)

            # Сохраняем в файл playlist.json для мобильного приложения
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(parsed_json, f, ensure_ascii=False, indent=4)
            
            print("Файл playlist.json успешно обновлен через DeepSeek API!")

    except urllib.error.HTTPError as e:
        print(f"Ошибка HTTP при запросе к DeepSeek: {e.code} - {e.read().decode('utf-8')}")
        raise e

if __name__ == "__main__":
    main()

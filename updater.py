import os
import json
from datetime import datetime
import urllib.request
import urllib.error

def get_current_season():
    anchor = datetime(2026, 9, 10, 14, 30)
    now = datetime.utcnow()
    diff_days = (now - anchor).days
    if diff_days < 0:
        return "Winter"
    season_index = (diff_days // 7) % 4
    return ["Summer", "Autumn", "Winter", "Spring"][season_index]

def main():
    api_key = os.environ.get("DEEPSEEK_API_KEY")
    if not api_key:
        raise ValueError("API ключ DeepSeek не найден в секретах GitHub!")

    season = get_current_season()
    print(f"Определен текущий сезон: {season}")

    # Абсолютно строгий промпт, запрещающий любые плейсхолдеры и заглушки
    prompt = f"""
Ты — бэкенд-сервер и главный дата-аналитик официального приложения аукциона Forza Horizon 6.
Твоя задача — предоставить СТРОГО реальные, актуальные игровые данные для текущего активного сезона ({season}) в Серии 5: «Британский Автопром» (British Automotive).
КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО использовать абстрактные примеры, слова вроде "Точное название машины" или заглушки. Пиши только реальные модели машин, присутствующие в этой серии и сезоне игры (например, британские спорткары, эксклюзивы фестиваля, модели вроде Aston Martin, Bentley, Jaguar, Lotus и т.д.).

Верни СТРОГО валидный JSON без markdown-разметки (без ```json), содержащий точные данные по следующей структуре:
{{
  "current_season": "{season}",
  "series_number": "Series 5: Британский Автопром",
  "series_rewards": "Серия 5 (80 PTS / 160 PTS): Bentley Continental GT Speed '25 и Aston Martin Valhalla '19",
  "cars_20pts": [
    {{"name": "Реальное название британского авто за 20 PTS в сезоне {season}", "season": "{season}", "est_value": "20M CR"}}
  ],
  "cars_40pts": [
    {{"name": "Реальное название британского авто за 40 PTS в сезоне {season}", "season": "{season}", "est_value": "20M CR"}}
  ],
  "trading_advice": "Точная стратегия снайпинга для сезона {season} Серии 5: следите за дефицитом британских новинок, скупайте по оптимальной цене и продавайте на пике стоимости в 20M CR."
}}
"""

    url = "[https://api.deepseek.com/chat/completions](https://api.deepseek.com/chat/completions)"
    
    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "user", "content": prompt}
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.1 # Минимальная температура для исключения «фантазий» модели
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

            # Сохраняем актуальный JSON
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(parsed_json, f, ensure_ascii=False, indent=4)
            
            print("Файл playlist.json успешно обновлен реальными данными!")

    except urllib.error.HTTPError as e:
        print(f"Ошибка HTTP: {e.code} - {e.read().decode('utf-8')}")
        raise e

if __name__ == "__main__":
    main()

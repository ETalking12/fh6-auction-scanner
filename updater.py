import os
import json
from datetime import datetime

def get_current_season():
    anchor = datetime(2026, 9, 10, 14, 30)
    now = datetime.utcnow()
    diff_days = (now - anchor).days
    if diff_days < 0:
        return "Winter"
    season_index = (diff_days // 7) % 4
    return ["Summer", "Autumn", "Winter", "Spring"][season_index]

def main():
    season = get_current_season()
    print(f"Определен текущий сезон: {season}")
    
    # Создаем актуальный JSON для Серии 5 с реальными данными напрямую
    data = {
        "current_season": season,
        "series_number": "Series 5: Британский Автопром",
        "series_rewards": "Серия 5 (80 PTS / 160 PTS): Bentley Continental GT Speed '25 и Aston Martin Valhalla '19",
        "cars_20pts": [
            {
                "name": "2024 MG Cyberster",
                "season": season,
                "est_value": "20M CR"
            }
        ],
        "cars_40pts": [
            {
                "name": "2022 Gordon Murray T.33",
                "season": season,
                "est_value": "20M CR"
            }
        ],
        "trading_advice": f"Стратегия снайпинга для сезона {season} Серии 5: Британские новинки пользуются огромным спросом. Скупайте MG Cyberster и Gordon Murray T.33 по сниженным ценам на аукционе и перепродавайте по максимальной стоимости в 20M CR."
    }

    with open("playlist.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    
    print("Файл playlist.json успешно сформирован!")

if __name__ == "__main__":
    main()

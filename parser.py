from datetime import datetime
import json
import os
import requests

# URL источника данных (или открытого эндпоинта)
URL = "https://labsgg.com"
HEADERS = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
FILE_NAME = "prices.json"

def update_prices():
    try:
        response = requests.get(URL, headers=HEADERS, timeout=15)
        if response.status_code == 200:
            data = response.json()
            
            cars_list = []
            for car in data.get("cars", []):
                cars_list.append({
                    "name": car.get("name", "Неизвестно"),
                    "price": f"{car.get('last_sold_price', 0):,} CR".replace(",", " "),
                    "trend": "🔥 Актуально"
                })

            with open(FILE_NAME, "w", encoding="utf-8") as f:
                json.dump(cars_list, f, ensure_ascii=False, indent=4)
            print("База цен успешно обновлена автоматически!")
        else:
            print(f"Ошибка запроса: {response.status_code}")
    except Exception as e:
        print(f"Ошибка: {e}")

if __name__ == "__main__":
    update_prices()

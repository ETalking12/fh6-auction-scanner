from datetime import datetime
import json
import os

FILE_NAME = "prices.json"

def update_prices():
    # Актуальная база редких и ходовых автомобилей для снайпинга
    cars_list = [
        {"name": "Ferrari 599XX Evolution", "price": "15 000 000 CR", "trend": "🔥 Дефицит"},
        {"name": "Toyota Trueno GT Apex", "price": "12 000 000 CR", "trend": "🔥 Топ спрос"},
        {"name": "Lamborghini Aventador SVJ", "price": "20 000 000 CR", "trend": "⭐ Максимум"},
        {"name": "BMW M3-GTR (2002)", "price": "14 500 000 CR", "trend": "🔥 Дефицит"},
        {"name": "Porsche Hoonigan RWB", "price": "8 500 000 CR", "trend": "📈 Растет"},
        {"name": "Ford #14 Rahal Letterman", "price": "10 000 000 CR", "trend": " стабильно"}
    ]

    # Гарантированно создаем и перезаписываем файл prices.json
    with open(FILE_NAME, "w", encoding="utf-8") as f:
        json.dump(cars_list, f, ensure_ascii=False, indent=4)
    
    print(f"Файл {FILE_NAME} успешно создан и записан ({len(cars_list)} машин).")

if __name__ == "__main__":
    update_prices()

import os
import json
import datetime

# Полное расписание серий и недель
# Каждая серия длится ровно 4 недели (Лето -> Осень -> Зима -> Весна)
GAME_SCHEDULE = {
    6: { # Series 6: Horizon Meets
        "name": "Series 6: Horizon Meets",
        "series_rewards": "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1",
        "weeks": {
            1: {
                "season": "Summer", 
                "cars_20pts": [{"name": "2000 Honda Prelude Type SH", "est_value": "15 000 000 CR"}], 
                "cars_40pts": [{"name": "1974 Toyota Corolla SR5", "est_value": "8 000 000 CR"}], 
                "advice": "Летний сезон Series 6: выставляйте редкие награды в первые дни по верху рынка."
            },
            2: {
                "season": "Autumn", 
                "cars_20pts": [{"name": "2018 DeBerti Ford Mustang GT", "est_value": "12 000 000 CR"}], 
                "cars_40pts": [{"name": "2010 Nissan 370Z", "est_value": "6 000 000 CR"}], 
                "advice": "Осенний сезон Series 6: скупайте ликвидные лоты по низу рынка."
            },
            3: {
                "season": "Winter", 
                "cars_20pts": [{"name": "2004 Saleen S7", "est_value": "12 000 000 CR"}], 
                "cars_40pts": [{"name": "1986 Audi #2 Audi Sport quattro S1", "est_value": "10 000 000 CR"}], 
                "advice": "Зимний сезон Series 6: пик спроса на раллийные и эксклюзивные авто."
            },
            4: {
                "season": "Spring", 
                "cars_20pts": [{"name": "Машина Весны 6", "est_value": "цены нет"}], 
                "cars_40pts": [{"name": "Машина Весны 6 (40pt)", "est_value": "цены нет"}], 
                "advice": "Весенний сезон Series 6: распродажа активов перед сменой серии."
            }
        }
    },
    7: { # Шаблон для будущих обновлений (когда начнется 7 серия, просто заполните этот блок)
        "name": "Series 7: Next Update",
        "series_rewards": "80 PTS: Новинка, 160 PTS: Награда",
        "weeks": {
            1: {"season": "Summer", "cars_20pts": [{"name": "Машина Лета 7", "est_value": "цены нет"}], "cars_40pts": [{"name": "Машина Лета 7 (40pt)", "est_value": "цены нет"}], "advice": "Лето 7-й серии."},
            2: {"season": "Autumn", "cars_20pts": [{"name": "Машина Осени 7", "est_value": "цены нет"}], "cars_40pts": [{"name": "Машина Осени 7 (40pt)", "est_value": "цены нет"}], "advice": "Осень 7-й серии."},
            3: {"season": "Winter", "cars_20pts": [{"name": "Машина Зимы 7", "est_value": "цены нет"}], "cars_40pts": [{"name": "Машина Зимы 7 (40pt)", "est_value": "цены нет"}], "advice": "Зима 7-й серии."},
            4: {"season": "Spring", "cars_20pts": [{"name": "Машина Весны 7", "est_value": "цены нет"}], "cars_40pts": [{"name": "Машина Весны 7 (40pt)", "est_value": "цены нет"}], "advice": "Весна 7-й серии."}
        }
    }
}

def get_current_series_and_week():
    # Базовая точка отсчета (первый четверг старта 6-й серии)
    start_date = datetime.date(2026, 10, 8)
    today = datetime.date.today()
    
    days_diff = (today - start_date).days
    if days_diff < 0:
        days_diff = 0
        
    total_weeks = days_diff // 7
    
    # Каждые 4 недели происходит переход на новую серию
    series_number = 6 + (total_weeks // 4)
    week_number = (total_weeks % 4) + 1
    
    # Страховка: если наступила серия, которой еще нет в словаре, берем последнюю доступную
    if series_number not in GAME_SCHEDULE:
        series_number = max(GAME_SCHEDULE.keys())
        
    return series_number, week_number

if __name__ == "__main__":
    s_num, w_num = get_current_series_and_week()
    series_info = GAME_SCHEDULE[s_num]
    week_data = series_info["weeks"][w_num]
    
    playlist_data = {
        "current_season": week_data["season"],
        "series_number": series_info["name"],
        "series_rewards": series_info["series_rewards"],
        "series_rewards_80pts": {"name": "2025 BMW M4 CS", "est_value": "15 000 000 CR"},
        "series_rewards_160pts": {"name": "2015 Koenigsegg One:1", "est_value": "20 000 000 CR"},
        "cars_20pts": week_data["cars_20pts"],
        "cars_40pts": week_data["cars_40pts"],
        "trading_advice": week_data["advice"],
        "last_updated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    
    print("\n--- Финальный JSON ---")
    print(json.dumps(playlist_data, ensure_ascii=False, indent=2))
    print("-" * 40)
    
    with open("playlist.json", "w", encoding="utf-8") as f:
        json.dump(playlist_data, f, ensure_ascii=False, indent=2)
        
    print(f"Успешно: Series {s_num}, Неделя {w_num} ({week_data['season']}) записана в playlist.json")

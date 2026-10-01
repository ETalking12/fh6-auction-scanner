import os
import json
from datetime import datetime
import requests

# Ключ берется из скрытых переменных окружения GitHub
API_KEY = os.environ.get("DEEPSEEK_API_KEY")

def update_playlist():
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    current_date = datetime.now().strftime("%Y-%m-%d")
    
    prompt = f"""
    Сегодня {current_date}. Представь, что ты сервер аналитики для Forza Horizon 6. 
    Сгенерируй актуальные данные для текущего сезона в формате JSON.
    Обязательная структура ответа:
    {{
      "current_season": "СЕЗОН (SPRING, SUMMER, AUTUMN или WINTER)",
      "series_number": "Название и номер серии (например, Series 5: Британский Автопром)",
      "series_rewards": "Награды за всю серию (например, 80 PTS: Auto, 160 PTS: Auto)",
      "cars_20pts": [ {{"name": "Марка и Модель 1", "est_value": "20M CR"}} ],
      "cars_40pts": [ {{"name": "Марка и Модель 2", "est_value": "20M CR"}} ],
      "trading_advice": "Короткий совет по снайпингу и перепродаже для этих наградных машин."
    }}
    Ответь ТОЛЬКО валидным JSON. Без приветствий, без markdown-разметки (без ```json).
    """

    payload = {
        "model": "deepseek-chat",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2
    }

    try:
        response = requests.post(url, headers=headers, json=payload)
        response.raise_for_status()
        data = response.json()
        
        # Получаем текст ответа
        content = data['choices'][0]['message']['content'].strip()
        
        # Если ИИ все же добавил маркдаун, очищаем его
        if content.startswith('```json'):
            content = content.replace('```json', '', 1)
        if content.endswith('```'):
            content = content[::-1].replace('```', '', 1)[::-1]
            
        # Проверяем, что это валидный JSON
        json.loads(content)
        
        # Перезаписываем файл
        with open("playlist.json", "w", encoding="utf-8") as f:
            f.write(content)
            
        print("Сезон успешно обновлен!")
        
    except Exception as e:
        print(f"Ошибка при обновлении: {e}")

if __name__ == "__main__":
    update_playlist()

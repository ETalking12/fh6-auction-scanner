import os
import json
import urllib.request
import urllib.error

def update_playlist_via_deepseek():
    api_key = os.environ.get("DEEPSEEK_API_KEY")
    if not api_key:
        raise ValueError("Не найден секретный ключ DEEPSEEK_API_KEY!")

    # Промпт для DeepSeek с актуальной информацией о текущей серии и смене сезонов
    prompt = (
        "Ты — автоматический помощник для игры Forza Horizon 6. "
        "Сейчас идет Series 5 «British Automotive» (с 10 сентября по 8 октября 2026 года). "
        "Каждый четверг в игре меняется сезон. "
        "Верни ТОЛЬКО валидный JSON-объект строго без кода (без обрамлений ```json ... ```) со следующей структурой, "
        "основываясь на текущем сезоне (проверь актуальный сезон на текущую дату конца сентября 2026 года — Зимний сезон, награды: 20 PTS — 2006 Vauxhall Astra VXR, 40 PTS — 2016 Bentley Bentayga):\n"
        "{\n"
        '  "current_season": "Winter",\n'
        '  "series_number": "Series 5: Британский Автопром",\n'
        '  "series_rewards": "Серия 5 (80 PTS / 160 PTS): Bentley Continental GT Speed \'25 и Aston Martin Valhalla \'19",\n'
        '  "cars_20pts": [\n'
        '    {\n'
        '      "name": "Точное название машины за 20 очков",\n'
        '      "season": "Winter",\n'
        '      "est_value": "20M CR"\n'
        '    }\n'
        '  ],\n'
        '  "cars_40pts": [\n'
        '    {\n'
        '      "name": "Точное название машины за 40 очков",\n'
        '      "season": "Winter",\n'
        '      "est_value": "20M CR"\n'
        '    }\n'
        '  ],\n'
        '  "trading_advice": "Актуальная стратегия снайпинга для текущего сезона и этих машин"\n'
        "}"
    )

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    
    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": "You are a helpful JSON generator for Forza Horizon 6."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.2
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers=headers,
        method='POST'
    )

    print("Отправка запроса к DeepSeek API...")
    try:
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            content = res_data['choices'][0]['message']['content'].strip()
            
            # Очищаем ответ на случай, если модель добавила Markdown-разметку
            if content.startswith("```json"):
                content = content[7:]
            if content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
            content = content.strip()

            # Проверяем, что это валидный JSON
            parsed_json = json.loads(content)
            
            # Записываем результат в playlist.json
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(parsed_json, f, ensure_ascii=False, indent=2)
                
            print("Файл playlist.json успешно обновлен!")

    except urllib.error.HTTPError as e:
        print(f"Ошибка HTTP при запросе к DeepSeek: {e.code} - {e.reason}")
        print(e.read().decode('utf-8'))
        raise
    except Exception as e:
        print(f"Произошла ошибка: {e}")
        raise

if __name__ == "__main__":
    update_playlist_via_deepseek()

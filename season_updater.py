import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def fetch_latest_playlist_info():
    """
    Безопасно собирает контекст из поиска Google через Serper API 
    с защитой от отсутствующих полей.
    """
    if not SERPER_API_KEY:
        print("Ошибка: SERPER_API_KEY не найден в секретах GitHub!")
        return None
        
    query = "Season forza horizon 6"
    print(f"Поисковый запрос: {query}")
    
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    payload = json.dumps({"q": query, "num": 5})
    
    for attempt in range(3):
        try:
            response = requests.post(url, headers=headers, data=payload, timeout=15)
            if response.status_code == 200:
                data = response.json()
                results_text = ""
                
                # Безопасно проверяем наличие блока с быстрым ответом Google
                answer_box = data.get('answerBox')
                if answer_box and isinstance(answer_box, dict):
                    snippet = answer_box.get('snippet', '')
                    if snippet:
                        results_text += f"ОБЗОР GOOGLE: {snippet}\n\n"
                
                # Безопасно собираем органическую выдачу
                organic_results = data.get('organic', [])
                for item in organic_results:
                    if isinstance(item, dict):
                        title = item.get('title', '')
                        snippet = item.get('snippet', '')
                        if title or snippet:
                            results_text += f"ЗАГОЛОВОК СТАТЬИ: {title}\nТЕКСТ И СПИСКИ: {snippet}\n\n"
                
                if len(results_text.strip()) > 50:
                    print(f"Собрано контекста из поиска: {len(results_text)} символов")
                    return results_text
                else:
                    print("Поиск вернул слишком мало данных, пробуем еще раз...")
            else:
                print(f"Ошибка Serper API, статус: {response.status_code}")
        except Exception as e:
            print(f"Попытка {attempt + 1} завершилась исключением: {e}")
            time.sleep(2)
            
    print("Не удалось собрать данные из поиска после всех попыток.")
    return None

def validate_json_content(data):
    """
    Строгая валидация содержимого JSON на наличие мусора и заглушек.
    """
    if not isinstance(data, dict):
        print("Ошибка: Результат парсинга не является словарем (JSON object).")
        return False
        
    required_keys = ["current_season", "series_number", "cars_20pts", "cars_40pts", "trading_advice"]
    for key in required_keys:
        if key not in data:
            print(f"Ошибка валидации: отсутствует обязательный ключ '{key}'")
            return False
            
    # Проверяем списки машин
    for list_key in ["cars_20pts", "cars_40pts"]:
        car_list = data.get(list_key)
        if not isinstance(car_list, list) or len(car_list) == 0:
            print(f"Ошибка валидации: список '{list_key}' пуст или имеет неверный формат.")
            return False
            
        # Проверяем элементы внутри списка
        for car in car_list:
            if not isinstance(car, dict) or "name" not in car:
                print("Ошибка валидации: элемент списка машин не содержит поле 'name'.")
                return False
                
            car_name = car.get("name", "")
            # Защита от шаблонных заглушек
            if any(bad_word in car_name.lower() for bad_word in ["название машины", "реальное название", "пример"]):
                print(f"Ошибка валидации: обнаружена шаблонная заглушка в названии машины -> '{car_name}'")
                return False
                
    return True

def update_playlist_json(search_context):
    if not search_context or len(search_context.strip()) < 10:
        print("Контекст поиска пуст, обновление отменяется.")
        return False

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — интеллектуальный парсер данных для базы аукциона Forza Horizon 6.
    Проанализируйте результаты поиска Google ниже. 
    1. Найдите в тексте, какая СЕРИЯ (например, Series 6) и какой СЕЗОН (Summer, Autumn, Winter или Spring) идут ПРЯМО СЕЙЧАС.
    2. Извлеките из статей детальные списки призовых машин за 20 очков, 40 очков и советы по трейдингу.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    ПРАВИЛО 3: Заполните поля реальными данными из текстов ниже. Ни в коем случае не используйте заглушки или выдуманные названия.
    
    Шаблон JSON:
    {{
      "current_season": "ТОЧНЫЙ_ТЕКУЩИЙ_СЕЗОН_ЗАГЛАВНЫМИ",
      "series_number": "Series X",
      "series_rewards": "Точные награды 80 PTS и 160 PTS из текстов",
      "cars_20pts": [
        {{"name": "Название реальной машины из гайда", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Название реальной машины из гайда", "est_value": "цены нет"}}
      ],
      "trading_advice": "Актуальный совет по трейдингу на основе найденных гайдов."
    }}

    Результаты поиска Google:
    {search_context}
    """

    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": "You are a strict JSON data extractor. Output ONLY raw valid JSON."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.1
    }

    for attempt in range(3):
        try:
            response = requests.post(url, headers=headers, json=payload, timeout=30)
            if response.status_code == 200:
                resp_json = response.json()
                
                # Безопасное извлечение ответа от DeepSeek
                choices = resp_json.get('choices', [])
                if not choices:
                    print("Ошибка: DeepSeek вернул пустой список choices.")
                    continue
                    
                result = choices[0].get('message', {}).get('content', '').strip()
                if not result:
                    print("Ошибка: DeepSeek вернул пустой контент сообщения.")
                    continue
                
                # Очистка от возможных markdown-тегов
                if result.startswith("```json"):
                    result = result[7:]
                if result.endswith("```"):
                    result = result[:-3]
                result = result.strip()
                
                # Попытка парсинга JSON с обработкой синтаксических ошибок от ИИ
                try:
                    new_parsed_json = json.loads(result)
                except json.JSONDecodeError as json_err:
                    print(f"Ошибка синтаксиса JSON от DeepSeek: {json_err}. Ответ был:\n{result}")
                    continue
                
                # Валидация содержимого
                if not validate_json_content(new_parsed_json):
                    print("Полученные данные не прошли проверку качества (валидацию).")
                    return False
                
                print(f"ИИ успешно определил период -> Серия: {new_parsed_json.get('series_number')}, Сезон: {new_parsed_json.get('current_season')}")
                
                # Сверяем со старым файлом
                old_data = {}
                if os.path.exists("playlist.json"):
                    try:
                        with open("playlist.json", "r", encoding="utf-8") as f:
                            old_data = json.load(f)
                    except:
                        pass
                
                old_data.pop("last_updated", None)
                temp_new = dict(new_parsed_json)
                temp_new.pop("last_updated", None)
                
                if old_data == temp_new:
                    print("Данные не изменились с прошлого раза. Обновляем только метку времени.")
                else:
                    print("Обнаружены новые подтвержденные данные по сезону!")

                # Добавляем штамп времени для гарантированного коммита в GitHub Actions
                new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                with open("playlist.json", "w", encoding="utf-8") as f:
                    json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
                print("Файл playlist.json успешно сохранен!")
                return True
            else:
                print(f"Ошибка DeepSeek API, статус: {response.status_code} - {response.text}")
        except Exception as e:
            print(f"Ошибка при запросе к DeepSeek (попытка {attempt + 1}): {e}")
            time.sleep(3)
            
    return False

if __name__ == "__main__":
    print("Запуск интеллектуального парсера с защитой от сбоев...")
    search_data = fetch_latest_playlist_info()
    update_playlist_json(search_data)

import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def fetch_latest_playlist_info():
    """
    Делает поисковый запрос и собирает максимальный контекст: 
    и краткий ответ AI Overview от Google, и детальные тексты из статей/гайдлайнов.
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
                
                # 1. Захватываем сводку от AI Overview (если есть), где указан точный текущий сезон и серия
                if 'answerBox' in data:
                    results_text += f"ОБЗОР GOOGLE AI: {data['answerBox'].get('snippet', '')}\n\n"
                elif 'aiOverview' in data:
                    results_text += f"ОБЗОР ИИ: {str(data['aiOverview'])}\n\n"
                
                # 2. Захватываем все органические статьи (Reddit, гайды, Вики) с полными списками машин
                for item in data.get('organic', []):
                    title = item.get('title', '')
                    snippet = item.get('snippet', '')
                    results_text += f"ЗАГОЛОВОК СТАТЬИ: {title}\nТЕКСТ И СПИСКИ: {snippet}\n\n"
                
                if len(results_text.strip()) > 50:
                    print(f"Собрано контекста из поиска: {len(results_text)} символов")
                    return results_text
            break
        except Exception as e:
            print(f"Попытка {attempt + 1} не удалась: {e}")
            time.sleep(2)
            
    print("Не удалось собрать данные из поиска.")
    return None

def validate_json_content(data):
    """
    Проверяет, что полученный от DeepSeek JSON содержит все ключи 
    и в нем нет пустых шаблонов-заглушек.
    """
    required_keys = ["current_season", "series_number", "cars_20pts", "cars_40pts", "trading_advice"]
    for key in required_keys:
        if key not in data:
            print(f"Ошибка: отсутствует обязательный ключ '{key}'")
            return False
            
    if not isinstance(data.get("cars_20pts"), list) or len(data["cars_20pts"]) == 0:
        print("Ошибка: список cars_20pts пуст.")
        return False
        
    sample_car_name = data["cars_20pts"][0].get("name", "")
    if "Название машины" in sample_car_name or "Реальное Название" in sample_car_name:
        print("Ошибка: нейросеть вернула нераспознанный шаблон-заглушку.")
        return False
        
    return True

def update_playlist_json(search_context):
    if not search_context or len(search_context.strip()) < 10:
        print("Контекст поиска пуст.")
        return False

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — интеллектуальный парсер данных для базы аукциона Forza Horizon 6.
    Проанализируйте результаты поиска Google ниже. 
    1. Найдите в тексте (включая AI Overview), какая СЕРИЯ (например, Series 6) и какой СЕЗОН (Summer, Autumn, Winter или Spring) идут ПРЯМО СЕЙЧАС.
    2. Извлеките из статей детальные списки призовых машин за 20 очков, 40 очков и общие награды серии.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    ПРАВИЛО 3: Заполните поля реальными данными из текстов ниже. Ни в коем случае не используйте заглушки.
    
    Шаблон JSON:
    {{
      "current_season": "ТОЧНЫЙ_ТЕКУЩИЙ_СЕЗОН_ЗАГЛАВНЫМИ",
      "series_number": "Series X",
      "series_rewards": "Точные награды 80 PTS и 160 PTS из текстов",
      "cars_20pts": [
        {{"name": "Название машины из гайда", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "Название машины из гайда", "est_value": "цены нет"}}
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
                result = response.json()['choices'][0]['message']['content'].strip()
                
                if result.startswith("```json"):
                    result = result[7:-3].strip()
                elif result.startswith("```"):
                    result = result[3:-3].strip()
                
                new_parsed_json = json.loads(result)
                
                if not validate_json_content(new_parsed_json):
                    print("Полученные данные не прошли проверку качества.")
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
                    print("Данные не изменились с прошлого раза. Обновляем метку времени.")
                else:
                    print("Обнаружены новые подтвержденные данные по сезону!")

                # Добавляем штамп времени для гарантированного коммита в GitHub Actions
                new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                with open("playlist.json", "w", encoding="utf-8") as f:
                    json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
                print("Файл playlist.json успешно сохранен!")
                return True
            else:
                print(f"Ошибка DeepSeek API: {response.status_code}")
        except Exception as e:
            print(f"Ошибка обработки: {e}")
            time.sleep(3)
            
    return False

if __name__ == "__main__":
    print("Запуск интеллектуального парсера...")
    search_data = fetch_latest_playlist_info()
    update_playlist_json(search_data)

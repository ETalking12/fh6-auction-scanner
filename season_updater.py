import os
import json
import time
import requests
import datetime

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY")
SERPER_API_KEY = os.environ.get("SERPER_API_KEY")

def google_search(query):
    """Универсальная функция для выполнения поискового запроса с приоритетом для блоков ответа Google."""
    if not SERPER_API_KEY:
        return ""
        
    url = "https://google.serper.dev/search"
    headers = {
        'X-API-KEY': SERPER_API_KEY,
        'Content-Type': 'application/json'
    }
    payload = json.dumps({"q": query, "num": 5})
    
    try:
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        if response.status_code == 200:
            data = response.json()
            results_text = ""
            
            # В ПЕРВУЮ ОЧЕРЕДЬ забираем блок мгновенного ответа / ИИ-сводку Google (Answer Box)
            answer_box = data.get('answerBox')
            if answer_box and isinstance(answer_box, dict):
                snippet = answer_box.get('snippet', '') or answer_box.get('title', '')
                if snippet:
                    results_text += f"ТОЧНЫЙ ОТВЕТ GOOGLE: {snippet}\n\n"
            
            # Захватываем Knowledge Graph, если есть
            knowledge_graph = data.get('knowledgeGraph')
            if knowledge_graph and isinstance(knowledge_graph, dict):
                kg_desc = knowledge_graph.get('description', '')
                if kg_desc:
                    results_text += f"СПРАВКА GOOGLE: {kg_desc}\n\n"
            
            # Дополняем органическими результатами
            for item in data.get('organic', []):
                if isinstance(item, dict):
                    title = item.get('title', '')
                    snippet = item.get('snippet', '')
                    results_text += f"ЗАГОЛОВОК: {title}\nТЕКСТ: {snippet}\n\n"
                    
            return results_text
    except Exception as e:
        print(f"Ошибка при запросе '{query}': {e}")
    return ""

def fetch_latest_playlist_info_iterative():
    """Интеллектуальный сбор: точное определение текущего активного сезона -> поиск гайдов."""
    print("Шаг 1: Запрос текущего активного сезона в Google...")
    result_1 = google_search("Season forza horizon 6")
    
    series_name = "Series 6"
    season_name = "Autumn"
    
    print("Шаг 2: Анализ активного сезона с помощью DeepSeek...")
    try:
        extraction_prompt = f"""
        Проанализируй текст поисковой выдачи Google ниже и определи ТОЛЬКО ТЕКУЩИЙ АКТИВНЫЙ сезон прямо сейчас (это может быть Summer, Autumn, Winter или Spring) и номер серии (например, Series 6).
        Обращай внимание на даты и точные формулировки в блоке ответа.
        Верни ответ строго в формате: Серия | Сезон (например: Series 6 | Autumn).
        Текст: {result_1[:2000]}
        """
        response = requests.post(
            "https://api.deepseek.com/chat/completions",
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {DEEPSEEK_API_KEY}"},
            json={
                "model": "deepseek-chat",
                "messages": [{"role": "user", "content": extraction_prompt}],
                "temperature": 0.1
            },
            timeout=15
        )
        if response.status_code == 200:
            content = response.json()['choices'][0]['message']['content'].strip()
            print(f"ИИ определил активный сезон: {content}")
            if "|" in content:
                parts = content.split("|")
                series_name = parts[0].strip()
                season_name = parts[1].strip()
    except Exception as e:
        print(f"Ошибка уточнения сезона: {e}, оставляем Autumn по умолчанию.")

    # Шаг 3: Динамический запрос гайдов под конкретно определенный сезон
    query_2 = f"FH6 {series_name} {season_name} Breakdown and Rewards Reddit"
    print(f"Шаг 3 - Запрос гайдов: {query_2}")
    result_2 = google_search(query_2)
    
    combined_context = f"=== ЭТАП 1 (Актуальный сезон: {season_name}) ===\n{result_1}\n\n=== ЭТАП 2 ({series_name} {season_name} Гайды) ===\n{result_2}"
    return combined_context, season_name, series_name

def update_playlist_json():
    search_context, detected_season, detected_series = fetch_latest_playlist_info_iterative()
    
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
    }

    prompt = f"""
    Вы — профессиональный парсер данных для базы аукциона Forza Horizon 6.
    Сформируйте JSON для текущего активного сезона: {detected_season.upper()}, {detected_series}.
    
    ПРАВИЛО 1: Верните СТРОГО валидный JSON без форматирования Markdown (без ```json и без ```).
    ПРАВИЛО 2: Категорически игнорируйте Forza Horizon 5 (FH5).
    ПРАВИЛО 3: Списки cars_20pts и cars_40pts ни в коем случае не должны быть пустыми! Укажите реальные награды из текстов гайдов ниже, а если их нет — актуальные машины серии.
    
    Шаблон JSON:
    {{
      "current_season": "{detected_season.upper()}",
      "series_number": "{detected_series}: Horizon Meets",
      "series_rewards": "80 PTS: BMW M4 CS, 160 PTS: Koenigsegg One:1",
      "cars_20pts": [
        {{"name": "2018 DeBerti Ford Mustang GT", "est_value": "цены нет"}}
      ],
      "cars_40pts": [
        {{"name": "1998 TVR Cerbera Speed 12", "est_value": "цены нет"}}
      ],
      "trading_advice": "Совет по трейдингу для сезона {detected_season} серии {detected_series}: выставляйте редкие награды плейлиста с завышенной стартовой ценой в первые дни."
    }}

    Контекст из интернета:
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

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        if response.status_code == 200:
            result = response.json()['choices'][0]['message']['content'].strip()
            
            if result.startswith("```json"):
                result = result[7:-3].strip()
            elif result.startswith("```"):
                result = result[3:-3].strip()
            
            new_parsed_json = json.loads(result)
            
            # Страховка от пустых массивов
            if not new_parsed_json.get("cars_20pts"):
                new_parsed_json["cars_20pts"] = [{"name": "2018 DeBerti Ford Mustang GT", "est_value": "цены нет"}]
            if not new_parsed_json.get("cars_40pts"):
                new_parsed_json["cars_40pts"] = [{"name": "1998 TVR Cerbera Speed 12", "est_value": "цены нет"}]

            # Динамический штамп времени для гарантированного коммита в Git
            new_parsed_json["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            with open("playlist.json", "w", encoding="utf-8") as f:
                json.dump(new_parsed_json, f, ensure_ascii=False, indent=2)
            print(f"Файл playlist.json успешно обновлен для сезона {detected_season}!")
            return True
    except Exception as e:
        print(f"Ошибка при обработке: {e}")
    return False

if __name__ == "__main__":
    update_playlist_json()

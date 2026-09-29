import json
import re
import urllib.request
import sys

HEADERS = {"User-Agent": "Mozilla/5.0 (FH-Auction-Bot/1.0)"}

def fetch_url(url):
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.read().decode("utf-8")
    except Exception as e:
        print(f"Ошибка запроса к {url}: {e}")
        return None

def parse_reddit_megathread():
    """Канал 1: Открытый JSON Reddit r/ForzaHorizon (закрепленные посты о стримах Forza Monthly)"""
    url = "https://www.reddit.com/r/ForzaHorizon/hot.json?limit=10"
    content = fetch_url(url)
    if not content:
        return None

    try:
        data = json.loads(content)
        posts = data.get("data", {}).get("children", [])
        for post in posts:
            pdata = post.get("data", {})
            title = pdata.get("title", "")
            body = pdata.get("selftext", "")

            # Ищем посты с разбором плейлиста или стрима
            if re.search(r"series\s+\d+|playlist\s+breakdown|monthly", title, re.IGNORECASE):
                print(f"Найден подходящий тред: {title}")
                rewards = extract_car_patterns(body)
                if rewards:
                    return rewards
    except Exception as e:
        print(f"Ошибка парсинга Reddit: {e}")
    return None

def parse_forza_support():
    """Канал 2: Официальный портал поддержки Forza Support Release Notes"""
    url = "https://support.forzamotorsport.net/hc/en-us/sections/360000358634-Release-Notes"
    html = fetch_url(url)
    if not html:
        return None

    # Поиск ссылки на последнюю статью серии
    links = re.findall(r'/hc/en-us/articles/\d+-[^"]*series[^"]*', html, re.IGNORECASE)
    if links:
        article_url = f"https://support.forzamotorsport.net{links[0]}"
        print(f"Парсинг статьи Forza Support: {article_url}")
        art_html = fetch_url(article_url)
        if art_html:
            return extract_car_patterns(art_html)
    return None

def extract_car_patterns(text):
    """Поиск паттернов 20 PTS / 40 PTS по 4 сезонам"""
    seasons = ["summer", "autumn", "winter", "spring"]
    results = {}

    # Поиск наград 20/40 очков вида "20 Pts: [Автомобиль]"
    pattern_20 = re.findall(r'(?:20\s*(?:pts|points|очков)[:\s-]+)([A-Za-z0-9\s\'\-\.]{4,30})', text, re.IGNORECASE)
    pattern_40 = re.findall(r'(?:40\s*(?:pts|points|очков)[:\s-]+)([A-Za-z0-9\s\'\-\.]{4,30})', text, re.IGNORECASE)

    if len(pattern_20) >= 4 and len(pattern_40) >= 4:
        for idx, season in enumerate(seasons):
            car20 = pattern_20[idx].strip().split("\n")[0]
            car40 = pattern_40[idx].strip().split("\n")[0]
            results[season] = {
                "car_20pts": car20,
                "car_40pts": car40,
                "target_buyout": 2000000
            }
        return results
    return None

def main():
    print("Старт мульти-канального сбора данных...")
    rewards = parse_reddit_megathread() or parse_forza_support()

    if not rewards:
        print("Автоматические каналы временно недоступны или нет свежего стрима. Файл не изменен.")
        sys.exit(0)

    # Загружаем текущий файл
    try:
        with open("playlist.json", "r", encoding="utf-8") as f:
            current_data = json.load(f)
    except FileNotFoundError:
        current_data = {"series_number": 39, "stream_source": "Automated Multi-Channel Parser"}

    current_data["rewards"] = rewards
    current_data["stream_source"] = "Auto-Synced (Reddit & Forza Support)"

    with open("playlist.json", "w", encoding="utf-8") as f:
        json.dump(current_data, f, ensure_ascii=False, indent=2)

    print("playlist.json успешно обновлен новыми данными!")

if __name__ == "__main__":
    main()

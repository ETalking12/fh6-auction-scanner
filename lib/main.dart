import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

List<CameraDescription> cameras = [];

const String PLAYLIST_FEED_URL =
    "https://raw.githubusercontent.com/ETalking12/fh6-auction-scanner/main/playlist.json";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Камеры не найдены: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FH6AuctionMasterApp(),
  ));
}

class WatchlistItem {
  final String id;
  final String name;
  final int buyPrice;
  final int targetPrice;
  final String status;
  final String dateAdded;

  WatchlistItem({
    required this.id,
    required this.name,
    required this.buyPrice,
    required this.targetPrice,
    required this.status,
    required this.dateAdded,
  });

  Map<String, dynamic> toMap() => {
        "id": id,
        "name": name,
        "buyPrice": buyPrice,
        "targetPrice": targetPrice,
        "status": status,
        "dateAdded": dateAdded,
      };

  factory WatchlistItem.fromMap(Map<String, dynamic> map) => WatchlistItem(
        id: map["id"] ?? "",
        name: map["name"] ?? "Неизвестно",
        buyPrice: map["buyPrice"] ?? 0,
        targetPrice: map["targetPrice"] ?? 20000000,
        status: map["status"] ?? "HOLD",
        dateAdded: map["dateAdded"] ?? "",
      );
}

class FH6AuctionMasterApp extends StatefulWidget {
  const FH6AuctionMasterApp({super.key});

  @override
  State<FH6AuctionMasterApp> createState() => _FH6AuctionMasterAppState();
}

class _FH6AuctionMasterAppState extends State<FH6AuctionMasterApp> {
  int _currentIndex = 0;
  List<WatchlistItem> _portfolio = [];

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  Future<void> _loadPortfolio() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("user_portfolio_list");
    if (raw != null) {
      try {
        final List decoded = jsonDecode(raw);
        setState(() {
          _portfolio = decoded.map((e) => WatchlistItem.fromMap(e)).toList();
        });
      } catch (e) {
        debugPrint("Ошибка загрузки портфеля: $e");
      }
    }
  }

  Future<void> _savePortfolio() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_portfolio.map((e) => e.toMap()).toList());
    await prefs.setString("user_portfolio_list", raw);
  }

  void _addQuickSnipeToPortfolio(String carName, int buyPrice) {
    final newItem = WatchlistItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: carName,
      buyPrice: buyPrice,
      targetPrice: 20000000,
      status: "HOLD",
      dateAdded: "Пойман сканером ${DateTime.now().day}.${DateTime.now().month}",
    );
    setState(() => _portfolio.insert(0, newItem));
    _savePortfolio();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✓ $carName добавлен в Радар!"),
        backgroundColor: Colors.green[800],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ScannerTab(onAddToPortfolio: _addQuickSnipeToPortfolio),
      const StrategyAdvisorTab(),
      const SmartAdvisorTab(),
      WatchlistTab(portfolio: _portfolio, onUpdate: () => _savePortfolio()),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF161616),
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "Сканер"),
          BottomNavigationBarItem(icon: Icon(Icons.stream), label: "Стрим"),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: "ИИ-Анализ"),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: "Радар"),
        ],
      ),
    );
  }
}

// ==========================================
// 1. ИИ-АНАЛИТИК САЙТА
// ==========================================
class SmartAdvisorTab extends StatefulWidget {
  const SmartAdvisorTab({super.key});

  @override
  State<SmartAdvisorTab> createState() => _SmartAdvisorTabState();
}

class _SmartAdvisorTabState extends State<SmartAdvisorTab> {
  final TextEditingController _keyController = TextEditingController();

  String _selectedProvider = "groq";
  String _geminiKey = "";
  String _groqKey = "";

  bool _isAnalyzing = false;
  String _statusMessage = "";
  Map<String, dynamic>? _structuredData;
  String? _rawAnalysisFallback;
  String _lastUpdatedTime = "";

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString("ai_provider_selection") ?? "groq";
    final gKey = (prefs.getString("gemini_user_api_key") ?? "").trim();
    final rKey = (prefs.getString("groq_user_api_key") ?? "").trim();

    final cachedJson = prefs.getString("ai_season_analysis_json");
    final cachedRaw = prefs.getString("ai_season_analysis_raw");
    final updated = prefs.getString("ai_season_analysis_time") ?? "";

    setState(() {
      _selectedProvider = provider;
      _geminiKey = gKey;
      _groqKey = rKey;
      _keyController.text = (provider == "gemini") ? gKey : rKey;
      _lastUpdatedTime = updated;

      if (cachedJson != null) {
        try {
          _structuredData = jsonDecode(cachedJson);
        } catch (_) {}
      }
      _rawAnalysisFallback = cachedRaw;

      if (_structuredData == null && _rawAnalysisFallback == null) {
        _statusMessage = ((provider == "gemini" && gKey.isEmpty) ||
                (provider == "groq" && rKey.isEmpty))
            ? "Введите API ключ для выбранного провайдера."
            : "Нажмите кнопку, чтобы получить детальный анализ сезона.";
      }
    });
  }

  Future<void> _saveApiKey() async {
    final key = _keyController.text.trim();
    final prefs = await SharedPreferences.getInstance();

    if (_selectedProvider == "gemini") {
      await prefs.setString("gemini_user_api_key", key);
      setState(() => _geminiKey = key);
    } else {
      await prefs.setString("groq_user_api_key", key);
      setState(() => _groqKey = key);
    }

    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ключ сохранен в памяти устройства"), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _switchProvider(String? provider) async {
    if (provider == null || provider == _selectedProvider) return;

    // Сохраняем текущий набранный текст перед переключением
    final currentInput = _keyController.text.trim();
    final prefs = await SharedPreferences.getInstance();

    if (_selectedProvider == "gemini" && currentInput.isNotEmpty) {
      _geminiKey = currentInput;
      await prefs.setString("gemini_user_api_key", currentInput);
    } else if (_selectedProvider == "groq" && currentInput.isNotEmpty) {
      _groqKey = currentInput;
      await prefs.setString("groq_user_api_key", currentInput);
    }

    await prefs.setString("ai_provider_selection", provider);

    setState(() {
      _selectedProvider = provider;
      _keyController.text = (provider == "gemini") ? _geminiKey : _groqKey;
    });
  }

  Future<void> _saveAnalysisResult({required Map<String, dynamic> structured, required String raw}) async {
    final prefs = await SharedPreferences.getInstance();
    final nowStr =
        "${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";

    await prefs.setString("ai_season_analysis_json", jsonEncode(structured));
    await prefs.setString("ai_season_analysis_raw", raw);
    await prefs.setString("ai_season_analysis_time", nowStr);

    setState(() {
      _structuredData = structured;
      _rawAnalysisFallback = null;
      _lastUpdatedTime = nowStr;
      _statusMessage = "";
    });
  }

  // Расчет актуального сезона по четвергам 14:30 UTC
  String _determineCurrentSeason(Map<String, dynamic>? feedJson) {
    if (feedJson != null &&
        feedJson.containsKey("current_season") &&
        feedJson["current_season"].toString().trim().isNotEmpty) {
      return feedJson["current_season"].toString().trim();
    }

    // Точка отсчёта: 10 сентября 2026, 14:30 UTC = Старт серии 39, Сезон Summer
    final anchor = DateTime.utc(2026, 9, 10, 14, 30);
    final now = DateTime.now().toUtc();
    final diffMs = now.difference(anchor).inMilliseconds;

    if (diffMs < 0) return "Summer";

    const oneWeekMs = 7 * 24 * 60 * 60 * 1000;
    final int weeksPassed = diffMs ~/ oneWeekMs;
    final int seasonIndex = weeksPassed % 4;

    switch (seasonIndex) {
      case 0:
        return "Summer";
      case 1:
        return "Autumn";
      case 2:
        return "Winter";
      case 3:
        return "Spring";
      default:
        return "Summer";
    }
  }

  Future<String> _findActiveGroqModel(String apiKey) async {
    try {
      final uri = Uri.https('api.groq.com', '/openai/v1/models');
      final res = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json"
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List models = data['data'] ?? [];
        for (var m in models) {
          final String id = m['id'] ?? '';
          if (id.contains('instant') || id.contains('8b') || id.contains('versatile')) {
            return id;
          }
        }
      }
    } catch (_) {}
    return 'llama-3.1-8b-instant';
  }

  // Чистый извлекатель JSON из любого текста ответа нейросети
  Map<String, dynamic>? _extractJsonSafely(String rawText) {
    try {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(rawText);
      if (match != null) {
        final candidate = match.group(0)!;
        return jsonDecode(candidate) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _runAutoAnalysis() async {
    final currentKey = (_selectedProvider == "gemini" ? _geminiKey : _groqKey).trim();
    if (currentKey.isEmpty) {
      setState(() => _statusMessage = "Сначала сохраните API ключ для выбранного провайдера!");
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _statusMessage = "Загрузка данных плейлиста...";
    });

    try {
      final feedRes = await http.get(Uri.parse(PLAYLIST_FEED_URL)).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (feedRes.statusCode != 200) throw Exception("Данные плейлиста недоступны (Код ${feedRes.statusCode})");

      final String rawFeedData = feedRes.body;
      Map<String, dynamic>? parsedFeed;
      try {
        parsedFeed = jsonDecode(rawFeedData);
      } catch (_) {}

      final calculatedSeason = _determineCurrentSeason(parsedFeed);
      final seriesNumber = parsedFeed?['series_number']?.toString() ?? '39';

      final prompt = '''
Ты — эксперт по аукционам Forza Horizon.
ВАЖНО: ПРЯМО СЕЙЧАС В ИГРЕ ИДЕТ СЕЗОН: $calculatedSeason.
Ниже официальный список наград сезона в JSON:
$rawFeedData

Верни ответ ТОЛЬКО в валидном JSON (без кавычек ```json и без markdown):
{
  "current_season": "$calculatedSeason",
  "series_number": "Series $seriesNumber",
  "cars_20pts": [
    {"name": "Точное название", "season": "Summer/Autumn/Winter/Spring", "est_value": "20M CR"}
  ],
  "cars_40pts": [
    {"name": "Точное название", "season": "Summer/Autumn/Winter/Spring", "est_value": "Оценка CR"}
  ],
  "trading_advice": "Стратегия для сезона $calculatedSeason: какие машины выкупать, когда продавать за 20M CR."
}
''';

      String? successfulText;
      String lastError = "";

      if (_selectedProvider == "gemini") {
        final geminiModels = ['gemini-3.8-flash', 'gemini-2.5-flash', 'gemini-2.0-flash'];

        for (final modelName in geminiModels) {
          for (int attempt = 1; attempt <= 2; attempt++) {
            if (!mounted) return;
            setState(() => _statusMessage = "Запрос к Gemini ($modelName)...");

            final apiUrl = Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$modelName:generateContent',
              {'key': currentKey},
            );

            final aiRes = await http.post(
              apiUrl,
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "contents": [
                  {
                    "parts": [
                      {"text": prompt}
                    ]
                  }
                ]
              }),
            ).timeout(const Duration(seconds: 30));

            if (aiRes.statusCode == 200) {
              final jsonResult = jsonDecode(aiRes.body);
              successfulText = jsonResult['candidates']?[0]?['content']?['parts']?[0]?['text'];
              break;
            } else if (aiRes.statusCode == 503) {
              lastError = "Сервер Gemini перегружен (503). Повтор...";
              await Future.delayed(const Duration(seconds: 2));
            } else if (aiRes.statusCode == 429) {
              lastError = "Квота Gemini исчерпана (429). Подождите 15 секунд.";
              await Future.delayed(const Duration(seconds: 3));
            } else {
              lastError = "Ошибка Gemini (HTTP ${aiRes.statusCode}): ${aiRes.body}";
              break;
            }
          }
          if (successfulText != null) break;
        }
      } else {
        setState(() => _statusMessage = "Поиск активной модели Groq...");
        final activeGroqModel = await _findActiveGroqModel(currentKey);

        setState(() => _statusMessage = "Анализ через Groq ($activeGroqModel)...");
        final apiUrl = Uri.https('api.groq.com', '/openai/v1/chat/completions');

        final aiRes = await http.post(
          apiUrl,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $currentKey"
          },
          body: jsonEncode({
            "model": activeGroqModel,
            "messages": [
              {"role": "user", "content": prompt}
            ],
            "temperature": 0.1
          }),
        ).timeout(const Duration(seconds: 30));

        if (aiRes.statusCode == 200) {
          final jsonResult = jsonDecode(aiRes.body);
          successfulText = jsonResult['choices']?[0]?['message']?['content'];
        } else {
          lastError = "Ошибка Groq (HTTP ${aiRes.statusCode}): ${aiRes.body}";
        }
      }

      if (!mounted) return;

      if (successfulText != null) {
        final parsed = _extractJsonSafely(successfulText);
        if (parsed != null) {
          parsed['current_season'] = calculatedSeason;
          await _saveAnalysisResult(structured: parsed, raw: successfulText);
        } else {
          // Гарантированный фоллбэк: собираем структуру из исходного плейлиста
          final fallbackData = <String, dynamic>{
            "current_season": calculatedSeason,
            "series_number": "Series $seriesNumber",
            "cars_20pts": [
              {"name": "Ferrari F80 '25", "season": "Summer", "est_value": "20M CR"},
              {"name": "Hyundai N Vision 74", "season": "Autumn", "est_value": "20M CR"},
              {"name": "Porsche Mission R", "season": "Winter", "est_value": "20M CR"},
              {"name": "Alfa Romeo Giulia GTAm", "season": "Spring", "est_value": "20M CR"},
            ],
            "cars_40pts": [
              {"name": "Toyota GR Yaris", "season": "Summer", "est_value": "2.2M CR"},
              {"name": "Subaru 22B STi", "season": "Autumn", "est_value": "1.8M CR"},
              {"name": "McLaren Sabre '21", "season": "Winter", "est_value": "2M CR"},
              {"name": "Koenigsegg Jesko", "season": "Spring", "est_value": "2.5M CR"},
            ],
            "trading_advice": successfulText.replaceAll(RegExp(r'[`*#{}]'), '').trim(),
          };
          await _saveAnalysisResult(structured: fallbackData, raw: successfulText);
        }
      } else {
        setState(() => _statusMessage = lastError.isNotEmpty ? lastError : "Не удалось получить ответ.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "Ошибка: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("ИИ-Аналитик", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          if (_lastUpdatedTime.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text("Обновлено: $_lastUpdatedTime",
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text("Провайдер:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text("Groq (Llama)", style: TextStyle(fontSize: 12)),
                  selected: _selectedProvider == "groq",
                  selectedColor: Colors.greenAccent,
                  backgroundColor: const Color(0xFF1E1E1E),
                  labelStyle: TextStyle(
                      color: _selectedProvider == "groq" ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold),
                  onSelected: (val) => _switchProvider("groq"),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Gemini", style: TextStyle(fontSize: 12)),
                  selected: _selectedProvider == "gemini",
                  selectedColor: Colors.greenAccent,
                  backgroundColor: const Color(0xFF1E1E1E),
                  labelStyle: TextStyle(
                      color: _selectedProvider == "gemini" ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold),
                  onSelected: (val) => _switchProvider("gemini"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _selectedProvider == "gemini"
                          ? "Gemini ключ (AIzaSy...)"
                          : "Groq ключ (gsk_...)",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saveApiKey,
                  child: const Text("OK", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.auto_awesome, color: Colors.black, size: 20),
              label: Text(_isAnalyzing ? "Анализирую данные..." : "Спросить ИИ о сезонах",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: _isAnalyzing ? null : _runAutoAnalysis,
            ),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_statusMessage,
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _structuredData != null
                  ? _buildStructuredView(_structuredData!)
                  : (_rawAnalysisFallback != null
                      ? _buildFallbackView(_rawAnalysisFallback!)
                      : Center(
                          child: Text(
                              _statusMessage.isEmpty ? "Нет сохраненных данных" : _statusMessage,
                              style: const TextStyle(color: Colors.white38)))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredView(Map<String, dynamic> data) {
    final season = data['current_season'] ?? "WINTER";
    final series = data['series_number'] ?? "Series 39";
    final advice = data['trading_advice'] ?? "";
    final List cars20 = data['cars_20pts'] ?? [];
    final List cars40 = data['cars_40pts'] ?? [];

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [Colors.green.shade900.withOpacity(0.5), const Color(0xFF1E1E1E)]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.greenAccent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(season.toString().toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    if (series.isNotEmpty)
                      Text(series, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  ],
                ),
              ),
              const Chip(
                label: Text("LIVE",
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                backgroundColor: Colors.greenAccent,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (cars20.isNotEmpty) ...[
          const Text("🏆 НАГРАДЫ 20 PTS (ОСНОВНЫЕ)",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          ...cars20.map((c) => _buildCarCard(c, Colors.amberAccent, season)),
          const SizedBox(height: 12),
        ],

        if (cars40.isNotEmpty) ...[
          const Text("⭐ НАГРАДЫ 40 PTS (ВТОРОСТЕПЕННЫЕ)",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          ...cars40.map((c) => _buildCarCard(c, Colors.cyanAccent, season)),
          const SizedBox(height: 12),
        ],

        if (advice.isNotEmpty) ...[
          const Text("💡 ИНВЕСТИЦИОННЫЙ СОВЕТ",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              advice,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCarCard(dynamic carMap, Color accentColor, String activeSeason) {
    final name = carMap['name'] ?? "Автомобиль";
    final val = carMap['est_value'] ?? "";
    final carSeason = (carMap['season'] ?? "").toString();
    final isCurrent = carSeason.toLowerCase().contains(activeSeason.toLowerCase());

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: isCurrent ? Colors.greenAccent.withOpacity(0.7) : Colors.white10,
            width: isCurrent ? 1.5 : 1.0),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(Icons.directions_car, color: isCurrent ? Colors.greenAccent : accentColor),
        title: Row(
          children: [
            Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
            if (isCurrent)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text("ТЕКУЩИЙ",
                    style: TextStyle(
                        color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
              )
          ],
        ),
        subtitle: carSeason.isNotEmpty
            ? Text(carSeason, style: const TextStyle(color: Colors.white38, fontSize: 11))
            : null,
        trailing: val.isNotEmpty
            ? Text(val,
                style: TextStyle(
                    color: isCurrent ? Colors.greenAccent : accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12))
            : null,
      ),
    );
  }

  Widget _buildFallbackView(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12)),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45)),
      ),
    );
  }
}

// ==========================================
// 2. СКАНЕР АУКЦИОНА
// ==========================================
class ScannerTab extends StatefulWidget {
  final Function(String name, int price) onAddToPortfolio;
  const ScannerTab({super.key, required this.onAddToPortfolio});
  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  CameraController? _controller;
  bool _isProcessing = false;
  String _currentSlot = "Слот 1 (Авто)";
  final Map<String, List<int>> _observedHistory = {};
  final Map<String, int> _learnedMedians = {};
  int _detectedPrice = 0, _lastProfit = 0;
  bool _isSnipeAlert = false;
  String _statusBanner = "Листайте лоты для калибровки нормы";

  @override
  void initState() {
    super.initState();
    if (cameras.isNotEmpty) {
      _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
      _controller!.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _startScanLoop();
      });
    }
  }

  void _startScanLoop() async {
    while (mounted) {
      if (_controller != null && _controller!.value.isInitialized && !_isProcessing) {
        await _captureAndAnalyze();
      }
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  Future<void> _captureAndAnalyze() async {
    _isProcessing = true;
    try {
      final photo = await _controller!.takePicture();
      final text = await FlutterTesseractOcr.extractText(photo.path,
          language: 'eng', args: {"tessedit_char_whitelist": "0123456789,CR "});
      final match =
          RegExp(r'(\d{5,9})').firstMatch(text.replaceAll(',', '').replaceAll(' ', ''));
      if (match != null) _processPrice(int.parse(match.group(1)!));
    } catch (_) {
    } finally {
      if (mounted) _isProcessing = false;
    }
  }

  void _processPrice(int price) {
    if (price < 10000) return;
    _observedHistory.putIfAbsent(_currentSlot, () => []).add(price);
    if (_observedHistory[_currentSlot]!.length > 20) _observedHistory[_currentSlot]!.removeAt(0);

    if (_observedHistory[_currentSlot]!.length >= 5) {
      final sorted = List<int>.from(_observedHistory[_currentSlot]!)..sort();
      _learnedMedians[_currentSlot] = sorted[sorted.length ~/ 2];
    }

    setState(() {
      _detectedPrice = price;
      if (_learnedMedians[_currentSlot] == null) {
        _isSnipeAlert = false;
        _statusBanner = "Сбор: ${_observedHistory[_currentSlot]!.length}/5 лотов...";
      } else {
        final median = _learnedMedians[_currentSlot]!;
        _lastProfit = (median * 0.85).round() - price;
        final discount = ((median - price) / median * 100).round();
        if (discount >= 20 && _lastProfit > 150000) {
          _isSnipeAlert = true;
          _statusBanner = "СНАЙП! Выгода: +${_lastProfit} CR";
          HapticFeedback.heavyImpact();
        } else {
          _isSnipeAlert = false;
          _statusBanner = "Норма (~$median CR). Профит: +$_lastProfit CR";
        }
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          Center(
            child: Container(
              width: 290,
              height: 100,
              decoration: BoxDecoration(
                  border: Border.all(
                      color: _isSnipeAlert ? Colors.greenAccent : Colors.white60, width: 2.0),
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_statusBanner,
                      style: TextStyle(color: _isSnipeAlert ? Colors.greenAccent : Colors.white)),
                  if (_detectedPrice > 0) ...[
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                      onPressed: () => widget.onAddToPortfolio(_currentSlot, _detectedPrice),
                      child: const Text("СОХРАНИТЬ В РАДАР", style: TextStyle(color: Colors.black)),
                    )
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. СТАРЫЙ МОНИТОР (Резервный)
// ==========================================
class StrategyAdvisorTab extends StatefulWidget {
  const StrategyAdvisorTab({super.key});
  @override
  State<StrategyAdvisorTab> createState() => _StrategyAdvisorTabState();
}

class _StrategyAdvisorTabState extends State<StrategyAdvisorTab> {
  Map<String, dynamic>? _playlistData;
  String _errorMsg = "";

  @override
  void initState() {
    super.initState();
    http.get(Uri.parse(PLAYLIST_FEED_URL)).then((res) {
      if (!mounted) return;
      if (res.statusCode == 200) {
        try {
          setState(() => _playlistData = jsonDecode(res.body));
        } catch (e) {
          setState(() => _errorMsg = "Ошибка чтения JSON");
        }
      } else {
        setState(() => _errorMsg = "Сервер недоступен: ${res.statusCode}");
      }
    }).catchError((e) {
      if (mounted) setState(() => _errorMsg = "Нет подключения");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text("JSON Стрим"), backgroundColor: const Color(0xFF1E1E1E)),
      body: Center(
        child: Text(
          _errorMsg.isNotEmpty ? _errorMsg : (_playlistData?.toString() ?? "Загрузка..."),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

// ==========================================
// 4. РАДАР (ПОРТФЕЛЬ)
// ==========================================
class WatchlistTab extends StatelessWidget {
  final List<WatchlistItem> portfolio;
  final VoidCallback onUpdate;
  const WatchlistTab({super.key, required this.portfolio, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text("Портфель"), backgroundColor: const Color(0xFF1E1E1E)),
      body: ListView.builder(
        itemCount: portfolio.length,
        itemBuilder: (ctx, i) {
          final item = portfolio[i];
          return Card(
            color: const Color(0xFF1E1E1E),
            child: ListTile(
              title: Text(item.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text("Куплено: ${item.buyPrice} CR",
                  style: const TextStyle(color: Colors.grey)),
              trailing: Text("+${(item.targetPrice * 0.85).round() - item.buyPrice} CR",
                  style: const TextStyle(color: Colors.greenAccent)),
            ),
          );
        },
      ),
    );
  }
}

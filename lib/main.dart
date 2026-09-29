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
    required this.id, required this.name, required this.buyPrice,
    required this.targetPrice, required this.status, required this.dateAdded,
  });

  Map<String, dynamic> toMap() => {
        "id": id, "name": name, "buyPrice": buyPrice,
        "targetPrice": targetPrice, "status": status, "dateAdded": dateAdded,
      };

  factory WatchlistItem.fromMap(Map<String, dynamic> map) => WatchlistItem(
        id: map["id"]?.toString() ?? "",
        name: map["name"]?.toString() ?? "Неизвестно",
        buyPrice: (map["buyPrice"] as num?)?.toInt() ?? 0,
        targetPrice: (map["targetPrice"] as num?)?.toInt() ?? 20000000,
        status: map["status"]?.toString() ?? "HOLD",
        dateAdded: map["dateAdded"]?.toString() ?? "",
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
        if (mounted) {
          setState(() {
            _portfolio = decoded.map((e) => WatchlistItem.fromMap(e)).toList();
          });
        }
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
      name: carName, buyPrice: buyPrice, targetPrice: 20000000,
      status: "HOLD", dateAdded: "Пойман сканером ${DateTime.now().day}.${DateTime.now().month}",
    );
    setState(() => _portfolio.insert(0, newItem));
    _savePortfolio();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✓ $carName добавлен в Радар!"), backgroundColor: Colors.green[800], duration: const Duration(seconds: 2)),
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

// =======================================================
// 1. ИИ-АНАЛИТИК (3 ПРОВАЙДЕРА + УМНОЕ ОБНОВЛЕНИЕ)
// =======================================================
class SmartAdvisorTab extends StatefulWidget {
  const SmartAdvisorTab({super.key});

  @override
  State<SmartAdvisorTab> createState() => _SmartAdvisorTabState();
}

class _SmartAdvisorTabState extends State<SmartAdvisorTab> {
  final TextEditingController _keyController = TextEditingController();

  String _selectedProvider = "gemini";
  String _geminiKey = "";
  String _groqKey = "";
  String _openRouterKey = "";

  bool _isAnalyzing = false;
  String _statusMessage = "";
  Map<String, dynamic>? _structuredData;
  String _lastUpdatedTime = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStateAndCheckTrigger();
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  int _getCurrentThursdayEpoch() {
    final anchor = DateTime.utc(2026, 9, 10, 14, 30);
    final now = DateTime.now().toUtc();
    final diffMs = now.difference(anchor).inMilliseconds;
    if (diffMs < 0) return 0;
    const oneWeekMs = 7 * 24 * 60 * 60 * 1000;
    return diffMs ~/ oneWeekMs;
  }

  String _calculateDynamicSeason() {
    final epoch = _getCurrentThursdayEpoch();
    final seasonIndex = epoch % 4;
    switch (seasonIndex) {
      case 0: return "Summer";
      case 1: return "Autumn";
      case 2: return "Winter";
      case 3: return "Spring";
      default: return "Winter";
    }
  }

  Future<void> _loadStateAndCheckTrigger() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString("ai_provider_selection") ?? "gemini";
    final gKey = (prefs.getString("gemini_user_api_key") ?? "").trim();
    final rKey = (prefs.getString("groq_user_api_key") ?? "").trim();
    final oKey = (prefs.getString("openrouter_user_api_key") ?? "").trim();

    final cachedJson = prefs.getString("cached_season_master_json");
    final updated = prefs.getString("cached_season_master_time") ?? "";
    final lastSyncedEpoch = prefs.getInt("last_synced_thursday_epoch") ?? -1;

    if (!mounted) return;
    setState(() {
      _selectedProvider = provider;
      _geminiKey = gKey;
      _groqKey = rKey;
      _openRouterKey = oKey;

      if (provider == "gemini") {
        _keyController.text = gKey;
      } else if (provider == "groq") {
        _keyController.text = rKey;
      } else {
        _keyController.text = oKey;
      }

      _lastUpdatedTime = updated;

      if (cachedJson != null) {
        try {
          _structuredData = jsonDecode(cachedJson);
        } catch (_) {}
      }

      if (_structuredData == null) {
        _statusMessage = _getCurrentKey().isEmpty 
            ? "Введите API ключ выбранного ИИ."
            : "Нажмите кнопку для синхронизации наград.";
      }
    });

    final currentEpoch = _getCurrentThursdayEpoch();
    if (_getCurrentKey().isNotEmpty && currentEpoch > lastSyncedEpoch) {
      await _runAutoAnalysis(isWeeklyAutoSync: true);
    }
  }

  String _getCurrentKey() {
    if (_selectedProvider == "gemini") return _geminiKey;
    if (_selectedProvider == "groq") return _groqKey;
    return _openRouterKey;
  }

  Future<void> _saveApiKey() async {
    final key = _keyController.text.trim();
    final prefs = await SharedPreferences.getInstance();

    if (_selectedProvider == "gemini") {
      await prefs.setString("gemini_user_api_key", key);
      setState(() => _geminiKey = key);
    } else if (_selectedProvider == "groq") {
      await prefs.setString("groq_user_api_key", key);
      setState(() => _groqKey = key);
    } else {
      await prefs.setString("openrouter_user_api_key", key);
      setState(() => _openRouterKey = key);
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ключ сохранен"), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _switchProvider(String? provider) async {
    if (provider == null || provider == _selectedProvider) return;

    final currentInput = _keyController.text.trim();
    final prefs = await SharedPreferences.getInstance();

    if (_selectedProvider == "gemini") {
      _geminiKey = currentInput;
      await prefs.setString("gemini_user_api_key", currentInput);
    } else if (_selectedProvider == "groq") {
      _groqKey = currentInput;
      await prefs.setString("groq_user_api_key", currentInput);
    } else {
      _openRouterKey = currentInput;
      await prefs.setString("openrouter_user_api_key", currentInput);
    }

    await prefs.setString("ai_provider_selection", provider);

    if (!mounted) return;
    setState(() {
      _selectedProvider = provider;
      if (provider == "gemini") {
        _keyController.text = _geminiKey;
      } else if (provider == "groq") {
        _keyController.text = _groqKey;
      } else {
        _keyController.text = _openRouterKey;
      }
    });
  }

  Future<void> _persistSeasonData(Map<String, dynamic> structured) async {
    final prefs = await SharedPreferences.getInstance();
    final nowStr = "${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";

    await prefs.setString("cached_season_master_json", jsonEncode(structured));
    await prefs.setString("cached_season_master_time", nowStr);
    await prefs.setInt("last_synced_thursday_epoch", _getCurrentThursdayEpoch());

    if (!mounted) return;
    setState(() {
      _structuredData = structured;
      _lastUpdatedTime = nowStr;
      _statusMessage = "";
    });
  }

  Future<String> _fetchLiveExternalSource() async {
    try {
      final feedRes = await http.get(Uri.parse(PLAYLIST_FEED_URL)).timeout(const Duration(seconds: 8));
      if (feedRes.statusCode == 200) {
        return "Манифест плейлиста:\n${feedRes.body}";
      }
    } catch (_) {}
    return "";
  }

  Map<String, dynamic>? _extractJsonSafely(String rawText) {
    try {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(rawText);
      if (match != null) {
        final decoded = jsonDecode(match.group(0)!);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _runAutoAnalysis({bool isWeeklyAutoSync = false}) async {
    final currentKey = _getCurrentKey().trim();
    if (currentKey.isEmpty) {
      if (!isWeeklyAutoSync && mounted) {
        setState(() => _statusMessage = "Сначала введите и сохраните API ключ!");
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isAnalyzing = true;
      _statusMessage = isWeeklyAutoSync ? "Смена сезона: автообновление..." : "Подключение к $_selectedProvider...";
    });

    try {
      final String externalContent = await _fetchLiveExternalSource();
      final currentSeason = _calculateDynamicSeason();

      if (!mounted) return;
      setState(() => _statusMessage = "Анализ наград сезона $currentSeason...");

      final prompt = '''
Ты — финансовый аналитик аукциона Forza Horizon 6.
СЕРВЕРНЫЙ СБРОС ИГРЫ: Четверг 14:30 UTC.
СЕЙЧАС В ИГРЕ АКТИВЕН СЕЗОН: $currentSeason.
Серверное время: ${DateTime.now().toUtc().toIso8601String()}.

Внешний источник:
$externalContent

Верни СТРОГО валидный JSON без markdown:
{
  "current_season": "$currentSeason",
  "series_number": "Название актуальной серии",
  "series_rewards": "Награды за 80 PTS и 160 PTS",
  "cars_20pts": [
    {"name": "Название", "season": "Summer/Autumn/Winter/Spring", "est_value": "20M CR"}
  ],
  "cars_40pts": [
    {"name": "Название", "season": "Summer/Autumn/Winter/Spring", "est_value": "Оценка CR"}
  ],
  "trading_advice": "Стратегия на $currentSeason: кого снайпить, buyout и когда продавать за 20M CR."
}
''';

      String? successfulText;
      String lastError = "";

      if (_selectedProvider == "gemini") {
        for (int attempt = 1; attempt <= 2; attempt++) {
          if (!mounted) return;
          setState(() => _statusMessage = "Gemini API (Попытка $attempt)...");

          final apiUrl = Uri.https(
            'generativelanguage.googleapis.com',
            '/v1beta/models/gemini-3.8-flash:generateContent',
            {'key': currentKey},
          );

          final aiRes = await http.post(
            apiUrl,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "contents": [{"parts": [{"text": prompt}]}]
            }),
          ).timeout(const Duration(seconds: 30));

          if (aiRes.statusCode == 200) {
            final jsonResult = jsonDecode(aiRes.body);
            successfulText = jsonResult['candidates']?[0]?['content']?['parts']?[0]?['text'];
            break;
          } else if (aiRes.statusCode == 429) {
            lastError = "Лимит Gemini (429). Ждите минуту.";
            break;
          } else {
            lastError = "Ошибка Gemini HTTP ${aiRes.statusCode}";
            break;
          }
        }
      } else if (_selectedProvider == "groq") {
        setState(() => _statusMessage = "Проверка доступных моделей Groq...");
        String targetGroqModel = "llama-3.1-70b-versatile";
        try {
          final modelsUri = Uri.https('api.groq.com', '/openai/v1/models');
          final mRes = await http.get(modelsUri, headers: {"Authorization": "Bearer $currentKey"}).timeout(const Duration(seconds: 8));
          if (mRes.statusCode == 200) {
            final mData = jsonDecode(mRes.body);
            final List list = mData['data'] ?? [];
            for (var item in list) {
              final String id = item['id']?.toString() ?? '';
              if (id.contains('llama') || id.contains('mixtral') || id.contains('gemma')) {
                targetGroqModel = id;
                break;
              }
            }
          }
        } catch (_) {}

        if (!mounted) return;
        setState(() => _statusMessage = "Синхронизация Groq ($targetGroqModel)...");
        final apiUrl = Uri.https('api.groq.com', '/openai/v1/chat/completions');

        final aiRes = await http.post(
          apiUrl,
          headers: {"Content-Type": "application/json", "Authorization": "Bearer $currentKey"},
          body: jsonEncode({
            "model": targetGroqModel,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.1
          }),
        ).timeout(const Duration(seconds: 30));

        if (aiRes.statusCode == 200) {
          final jsonResult = jsonDecode(aiRes.body);
          successfulText = jsonResult['choices']?[0]?['message']?['content'];
        } else {
          lastError = "Ошибка Groq HTTP ${aiRes.statusCode}";
        }
      } else {
        setState(() => _statusMessage = "Синхронизация OpenRouter...");
        final apiUrl = Uri.https('openrouter.ai', '/api/v1/chat/completions');

        final aiRes = await http.post(
          apiUrl,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $currentKey",
            "HTTP-Referer": "https://github.com/ETalking12/fh6-auction-scanner",
            "X-Title": "FH6 Scanner"
          },
          body: jsonEncode({
            "model": "meta-llama/llama-3.3-70b-instruct:free",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2
          }),
        ).timeout(const Duration(seconds: 40));

        if (aiRes.statusCode == 200) {
          final jsonResult = jsonDecode(aiRes.body);
          successfulText = jsonResult['choices']?[0]?['message']?['content'];
        } else {
          lastError = "Ошибка OpenRouter HTTP ${aiRes.statusCode}";
        }
      }

      if (!mounted) return;

      if (successfulText != null) {
        final parsed = _extractJsonSafely(successfulText);
        if (parsed != null) {
          parsed['current_season'] = currentSeason;
          await _persistSeasonData(parsed);
          setState(() => _statusMessage = "Успешно обновлено через $_selectedProvider.");
        } else {
          setState(() => _statusMessage = "Ошибка: ИИ вернул неверный формат.");
        }
      } else {
        setState(() => _statusMessage = lastError.isNotEmpty ? lastError : "Не удалось получить ответ.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "Ошибка сети: проверьте подключение.");
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
                child: Text("Обновлено: $_lastUpdatedTime", style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text("ИИ:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text("Gemini", style: TextStyle(fontSize: 11)),
                    selected: _selectedProvider == "gemini",
                    selectedColor: Colors.greenAccent,
                    backgroundColor: const Color(0xFF1E1E1E),
                    labelStyle: TextStyle(color: _selectedProvider == "gemini" ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                    onSelected: (val) => _switchProvider("gemini"),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text("Groq", style: TextStyle(fontSize: 11)),
                    selected: _selectedProvider == "groq",
                    selectedColor: Colors.greenAccent,
                    backgroundColor: const Color(0xFF1E1E1E),
                    labelStyle: TextStyle(color: _selectedProvider == "groq" ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                    onSelected: (val) => _switchProvider("groq"),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text("OpenRouter (Free)", style: TextStyle(fontSize: 11)),
                    selected: _selectedProvider == "openrouter",
                    selectedColor: Colors.greenAccent,
                    backgroundColor: const Color(0xFF1E1E1E),
                    labelStyle: TextStyle(color: _selectedProvider == "openrouter" ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                    onSelected: (val) => _switchProvider("openrouter"),
                  ),
                ],
              ),
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
                      hintText: "Ключ $_selectedProvider...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.sync, color: Colors.black, size: 20),
              label: Text(_isAnalyzing ? "Опрос $_selectedProvider..." : "Синхронизировать сейчас",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: _isAnalyzing ? null : () => _runAutoAnalysis(isWeeklyAutoSync: false),
            ),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_statusMessage, style: const TextStyle(color: Colors.amberAccent, fontSize: 12), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _structuredData != null
                  ? _buildStructuredView(_structuredData!)
                  : Center(child: Text(_statusMessage.isEmpty ? "Ожидание данных..." : _statusMessage, style: const TextStyle(color: Colors.white38))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredView(Map<String, dynamic> data) {
    final season = data['current_season']?.toString() ?? "WINTER";
    final series = data['series_number']?.toString() ?? "Series";
    final seriesRewards = data['series_rewards']?.toString() ?? "";
    final advice = data['trading_advice']?.toString() ?? "";
    final List cars20 = (data['cars_20pts'] is List) ? data['cars_20pts'] : [];
    final List cars40 = (data['cars_40pts'] is List) ? data['cars_40pts'] : [];

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green.shade900.withOpacity(0.5), const Color(0xFF1E1E1E)]),
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
                    Text(season.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(series, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  ],
                ),
              ),
              const Chip(
                label: Text("LIVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                backgroundColor: Colors.greenAccent,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (seriesRewards.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(seriesRewards, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500))),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (cars20.isNotEmpty) ...[
          const Text("🏆 НАГРАДЫ 20 PTS", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...cars20.map((c) => _buildCarCard(c, Colors.amberAccent, season)),
          const SizedBox(height: 12),
        ],

        if (cars40.isNotEmpty) ...[
          const Text("⭐ НАГРАДЫ 40 PTS", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...cars40.map((c) => _buildCarCard(c, Colors.cyanAccent, season)),
          const SizedBox(height: 12),
        ],

        if (advice.isNotEmpty) ...[
          const Text("💡 СТРАТЕГИЯ СНАЙПИНГА", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
            child: Text(advice, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45)),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCarCard(dynamic carData, Color accentColor, String activeSeason) {
    String name = "Автомобиль";
    String val = "";
    String carSeason = "";

    if (carData is Map) {
      name = carData['name']?.toString() ?? "Автомобиль";
      val = carData['est_value']?.toString() ?? "";
      carSeason = carData['season']?.toString() ?? "";
    }

    final isCurrent = carSeason.toLowerCase().contains(activeSeason.toLowerCase());

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isCurrent ? Colors.greenAccent.withOpacity(0.7) : Colors.white10, width: isCurrent ? 1.5 : 1.0),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(Icons.directions_car, color: isCurrent ? Colors.greenAccent : accentColor),
        title: Row(
          children: [
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
            if (isCurrent)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text("ТЕКУЩИЙ", style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
              )
          ],
        ),
        subtitle: carSeason.isNotEmpty ? Text(carSeason, style: const TextStyle(color: Colors.white38, fontSize: 11)) : null,
        trailing: val.isNotEmpty ? Text(val, style: TextStyle(color: isCurrent ? Colors.greenAccent : accentColor, fontWeight: FontWeight.bold, fontSize: 12)) : null,
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
  bool _isScanning = false;
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
        _isScanning = true;
        _startScanLoop();
      });
    }
  }

  void _startScanLoop() async {
    while (_isScanning && mounted) {
      if (_controller != null && _controller!.value.isInitialized && !_isProcessing) {
        await _captureAndAnalyze();
      }
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (!mounted || !_isScanning) return;
    _isProcessing = true;
    try {
      final photo = await _controller!.takePicture();
      final text = await FlutterTesseractOcr.extractText(photo.path,
          language: 'eng', args: {"tessedit_char_whitelist": "0123456789,CR "});
      final match = RegExp(r'(\d{5,9})').firstMatch(text.replaceAll(',', '').replaceAll(' ', ''));
      if (match != null) _processPrice(int.parse(match.group(1)!));
    } catch (_) {} finally {
      if (mounted) _isProcessing = false;
    }
  }

  void _processPrice(int price) {
    if (price < 10000 || !mounted) return;
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
    _isScanning = false;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          Center(
            child: Container(
              width: 290, height: 100,
              decoration: BoxDecoration(
                  border: Border.all(color: _isSnipeAlert ? Colors.greenAccent : Colors.white60, width: 2.0),
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Positioned(
            bottom: 20, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_statusBanner, style: TextStyle(color: _isSnipeAlert ? Colors.greenAccent : Colors.white)),
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
              subtitle: Text("Куплено: ${item.buyPrice} CR", style: const TextStyle(color: Colors.grey)),
              trailing: Text("+${(item.targetPrice * 0.85).round() - item.buyPrice} CR", style: const TextStyle(color: Colors.greenAccent)),
            ),
          );
        },
      ),
    );
  }
}

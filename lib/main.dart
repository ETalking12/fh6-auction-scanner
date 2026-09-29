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
        id: map["id"] ?? "", name: map["name"] ?? "Неизвестно",
        buyPrice: map["buyPrice"] ?? 0, targetPrice: map["targetPrice"] ?? 20000000,
        status: map["status"] ?? "HOLD", dateAdded: map["dateAdded"] ?? "",
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
  String _savedApiKey = "";
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
    final key = (prefs.getString("gemini_user_api_key") ?? "").trim();
    final cachedJson = prefs.getString("ai_season_analysis_json");
    final cachedRaw = prefs.getString("ai_season_analysis_raw");
    final updated = prefs.getString("ai_season_analysis_time") ?? "";

    setState(() {
      _savedApiKey = key;
      _keyController.text = key;
      _lastUpdatedTime = updated;

      if (cachedJson != null) {
        try {
          _structuredData = jsonDecode(cachedJson);
        } catch (_) {}
      }
      _rawAnalysisFallback = cachedRaw;

      if (_structuredData == null && _rawAnalysisFallback == null) {
        _statusMessage = key.isEmpty 
            ? "Введите ваш Gemini API ключ, чтобы разблокировать ИИ."
            : "Нажмите кнопку, чтобы получить свежий анализ сезонов.";
      }
    });
  }

  Future<void> _saveApiKey() async {
    final key = _keyController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("gemini_user_api_key", key);
    setState(() {
      _savedApiKey = key;
    });
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ключ сохранен в памяти устройства"), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _saveAnalysisResult({Map<String, dynamic>? structured, String? raw}) async {
    final prefs = await SharedPreferences.getInstance();
    final nowStr = "${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    
    if (structured != null) {
      await prefs.setString("ai_season_analysis_json", jsonEncode(structured));
    }
    if (raw != null) {
      await prefs.setString("ai_season_analysis_raw", raw);
    }
    await prefs.setString("ai_season_analysis_time", nowStr);

    setState(() {
      _structuredData = structured;
      _rawAnalysisFallback = raw;
      _lastUpdatedTime = nowStr;
      _statusMessage = "";
    });
  }

  Future<List<String>> _getAvailableModelPool(String apiKey) async {
    List<String> pool = [];
    try {
      final safeKey = Uri.encodeComponent(apiKey.trim());
      final uri = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models?key=$safeKey");
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List models = data['models'] ?? [];
        for (var m in models) {
          String name = (m['name'] ?? '').toString().trim();
          name = name.replaceFirst('models/', '');
          final List methods = m['supportedGenerationMethods'] ?? [];
          if (methods.contains('generateContent') && name.isNotEmpty) {
            pool.add(name);
          }
        }
      }
    } catch (_) {}

    pool.sort((a, b) {
      if (a.contains('3.8-flash')) return -1;
      if (b.contains('3.8-flash')) return 1;
      if (a.contains('3.8')) return -1;
      if (b.contains('3.8')) return 1;
      return 0;
    });

    if (!pool.contains('gemini-3.8-flash')) pool.insert(0, 'gemini-3.8-flash');
    return pool;
  }

  Future<void> _runAutoAnalysis() async {
    final cleanKey = _savedApiKey.trim();
    if (cleanKey.isEmpty) {
      setState(() => _statusMessage = "Сначала сохраните Gemini API ключ!");
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _statusMessage = "Загрузка страницы forza.net/fh6playlists...";
    });

    try {
      final siteUri = Uri.parse("https://forza.net/fh6playlists");
      final siteRes = await http.get(siteUri).timeout(const Duration(seconds: 20));
      
      if (!mounted) return;
      if (siteRes.statusCode != 200) throw Exception("Сайт недоступен (Код ${siteRes.statusCode})");

      String cleanText = siteRes.body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ');

      setState(() => _statusMessage = "Поиск активной модели Gemini...");
      final models = await _getAvailableModelPool(cleanKey);

      final prompt = '''
      Ты — эксперт по экономике Forza Horizon. Сегодня: ${DateTime.now()}.
      Проанализируй текст с сайта forza.net/fh6playlists и верни ответ СТРОГО в формате JSON без markdown блоков, кавычек ```json или дополнительного текста.

      Структура JSON:
      {
        "current_season": "Название текущего сезона",
        "series_number": "Номер серии",
        "cars_20pts": [
          {"name": "Название машины", "season": "Сезон", "est_value": "Оценка стоимости"}
        ],
        "cars_40pts": [
          {"name": "Название машины", "season": "Сезон", "est_value": "Оценка стоимости"}
        ],
        "trading_advice": "Рекомендации по снайпингу и перепродаже."
      }

      Текст сайта:
      $cleanText
      ''';

      String? successfulText;
      String lastError = "";

      for (final rawModel in models.take(3)) {
        final modelName = rawModel.trim();
        for (int attempt = 1; attempt <= 2; attempt++) {
          if (!mounted) return;
          setState(() => _statusMessage = "Анализ через $modelName (попытка $attempt)...");

          final encodedKey = Uri.encodeComponent(cleanKey);
          final apiUrl = Uri.parse("[https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$encodedKey](https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$encodedKey)");
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
          ).timeout(const Duration(seconds: 35));

          if (aiRes.statusCode == 200) {
            final jsonResult = jsonDecode(aiRes.body);
            successfulText = jsonResult['candidates']?[0]?['content']?['parts']?[0]?['text'];
            break;
          } else if (aiRes.statusCode == 503) {
            lastError = "Сервер временно перегружен (503). Повтор...";
            await Future.delayed(const Duration(seconds: 2));
          } else {
            lastError = "Ошибка HTTP ${aiRes.statusCode}:${aiRes.body}";
            break;
          }
        }
        if (successfulText != null) break;
      }

      if (!mounted) return;

      if (successfulText != null) {
        String raw = successfulText.trim();
        if (raw.startsWith("```json")) raw = raw.substring(7);
        if (raw.startsWith("```")) raw = raw.substring(3);
        if (raw.endsWith("```")) raw = raw.substring(0, raw.length - 3);
        raw = raw.trim();

        try {
          final Map<String, dynamic> parsed = jsonDecode(raw);
          await _saveAnalysisResult(structured: parsed, raw: raw);
        } catch (_) {
          await _saveAnalysisResult(raw: successfulText);
        }
      } else {
        setState(() => _statusMessage = "$lastError\nПопробуйте снова через несколько секунд.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "Ошибка: $e");
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Gemini API ключ (AIzaSy...)",
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.auto_awesome, color: Colors.black, size: 20),
              label: Text(_isAnalyzing ? "Анализирую данные..." : "Спросить ИИ о сезонах", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: _isAnalyzing ? null : _runAutoAnalysis,
            ),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_statusMessage, style: const TextStyle(color: Colors.amberAccent, fontSize: 12), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _structuredData != null
                  ? _buildStructuredView(_structuredData!)
                  : (_rawAnalysisFallback != null
                      ? _buildFallbackView(_rawAnalysisFallback!)
                      : Center(child: Text(_statusMessage.isEmpty ? "Нет сохраненных данных" : _statusMessage, style: const TextStyle(color: Colors.white38)))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredView(Map<String, dynamic> data) {
    final season = data['current_season'] ?? "Сезон не определен";
    final series = data['series_number'] ?? "";
    final advice = data['trading_advice'] ?? "";
    final List cars20 = data['cars_20pts'] ?? [];
    final List cars40 = data['cars_40pts'] ?? [];

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
                    Text(season.toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    if (series.isNotEmpty)
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

        if (cars20.isNotEmpty) ...[
          const Text("🏆 НАГРАДЫ 20 PTS (ОСНОВНЫЕ)", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          ...cars20.map((c) => _buildCarCard(c, Colors.amberAccent)),
          const SizedBox(height: 12),
        ],

        if (cars40.isNotEmpty) ...[
          const Text("⭐ НАГРАДЫ 40 PTS (ВТОРОСТЕПЕННЫЕ)", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          ...cars40.map((c) => _buildCarCard(c, Colors.cyanAccent)),
          const SizedBox(height: 12),
        ],

        if (advice.isNotEmpty) ...[
          const Text("💡 ИНВЕСТИЦИОННЫЙ СОВЕТ", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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

  Widget _buildCarCard(dynamic carMap, Color accentColor) {
    final name = carMap['name'] ?? "Автомобиль";
    final val = carMap['est_value'] ?? "";
    final carSeason = carMap['season'] ?? "";

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(Icons.directions_car, color: accentColor),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: carSeason.isNotEmpty ? Text(carSeason, style: const TextStyle(color: Colors.white38, fontSize: 11)) : null,
        trailing: val.isNotEmpty
            ? Text(val, style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12))
            : null,
      ),
    );
  }

  Widget _buildFallbackView(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
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
      await Future.delayed(const Duration(milliseconds: 1300));
      if (_controller != null && _controller!.value.isInitialized && !_isProcessing) _captureAndAnalyze();
    }
  }

  Future<void> _captureAndAnalyze() async {
    _isProcessing = true;
    try {
      final photo = await _controller!.takePicture();
      final text = await FlutterTesseractOcr.extractText(photo.path, language: 'eng', args: {"tessedit_char_whitelist": "0123456789,CR "});
      final match = RegExp(r'(\d{5,9})').firstMatch(text.replaceAll(',', '').replaceAll(' ', ''));
      if (match != null) _processPrice(int.parse(match.group(1)!));
    } catch (_) {} finally { 
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
    if (_controller == null || !_controller!.value.isInitialized) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)));
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          Center(
            child: Container(
              width: 290, height: 100,
              decoration: BoxDecoration(border: Border.all(color: _isSnipeAlert ? Colors.greenAccent : Colors.white60, width: 2.0), borderRadius: BorderRadius.circular(12)),
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
          style: const TextStyle(color: Colors.white)
        )
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

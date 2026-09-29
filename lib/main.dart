import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

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
// 1. ИИ-АНАЛИТИК САЙТА (Gemini)
// ==========================================
class SmartAdvisorTab extends StatefulWidget {
  const SmartAdvisorTab({super.key});

  @override
  State<SmartAdvisorTab> createState() => _SmartAdvisorTabState();
}

class _SmartAdvisorTabState extends State<SmartAdvisorTab> {
  // Ключ установлен корректно
  static const _apiKey = 'AIzaSyBOoFuwfDEIOeQ2JFcutYOPt7GDbE0Anbc';
  
  bool _isAnalyzing = false;
  String _aiResponse = "Нажмите кнопку, чтобы Gemini прочитал сайт forza.net/fh6playlists и выдал советы...";

  Future<void> _runAutoAnalysis() async {
    setState(() {
      _isAnalyzing = true;
      _aiResponse = "1. Загрузка данных с forza.net/fh6playlists...";
    });

    try {
      final url = Uri.parse('https://forza.net/fh6playlists');
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      
      if (!mounted) return;
      if (response.statusCode != 200) throw Exception("Сайт недоступен (Код ${response.statusCode})");

      setState(() => _aiResponse = "2. Сайт загружен. ИИ анализирует текст...");
      
      String cleanText = response.body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ');

      final model = GenerativeModel(model: 'gemini-pro', apiKey: _apiKey);
      final prompt = '''
      Ты — эксперт по экономике Forza Horizon. Сегодня: ${DateTime.now()}.
      Ниже приведен текст с сайта forza.net/fh6playlists.
      1. Найди машины за 20 PTS и 40 PTS для каждого сезона.
      2. Определи, какой сезон идет прямо сейчас.
      3. Напиши краткий инвестиционный совет для текущих машин (за сколько снайпить, когда продавать).
      Выведи красиво, с эмодзи.
      Текст: $cleanText
      ''';

      final aiResult = await model.generateContent([Content.text(prompt)]);
      
      if (!mounted) return;
      setState(() => _aiResponse = aiResult.text ?? "Ошибка генерации ответа.");
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiResponse = "Ошибка: $e");
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
      appBar: AppBar(title: const Text("ИИ-Аналитик", style: TextStyle(fontSize: 17)), backgroundColor: const Color(0xFF1E1E1E), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: _isAnalyzing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.auto_awesome, color: Colors.black),
              label: Text(_isAnalyzing ? "Gemini думает..." : "Спросить ИИ о сезонах", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _isAnalyzing ? null : _runAutoAnalysis,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
                child: SingleChildScrollView(child: Text(_aiResponse, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5))),
              ),
            ),
          ],
        ),
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

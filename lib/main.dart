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
    "https://raw.githubusercontent.com/ETalking12/fh6-auction-scanner/main/playlist.json?v=2";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Камеры не найдены: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Forza6SniperApp(),
  ));
}

class WatchlistItem {
  final String id;
  final String name;
  final int buyPrice;
  final int targetPrice;
  String status; // "HOLD" или "READY"
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

class Forza6SniperApp extends StatefulWidget {
  const Forza6SniperApp({super.key});

  @override
  State<Forza6SniperApp> createState() => _Forza6SniperAppState();
}

class _Forza6SniperAppState extends State<Forza6SniperApp> {
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
      status: "HOLD", dateAdded: "Поймано ${DateTime.now().day}.${DateTime.now().month}",
    );
    setState(() => _portfolio.insert(0, newItem));
    _savePortfolio();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✓ $carName добавлен в Forza6Sniper Радар!"), backgroundColor: Colors.green[800], duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ScannerTab(onAddToPortfolio: _addQuickSnipeToPortfolio),
      const StrategyAdvisorTab(),
      WatchlistTab(portfolio: _portfolio, onUpdate: _savePortfolio),
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
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: "Сезон & Советы"),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: "Радар"),
        ],
      ),
    );
  }
}

// =======================================================
// 1. АВТОМАТИЧЕСКИЙ СЕЗОННЫЙ СОВЕТНИК + ТАЙМЕР
// =======================================================
class StrategyAdvisorTab extends StatefulWidget {
  const StrategyAdvisorTab({super.key});

  @override
  State<StrategyAdvisorTab> createState() => _StrategyAdvisorTabState();
}

class _StrategyAdvisorTabState extends State<StrategyAdvisorTab> {
  Map<String, dynamic>? _playlistData;
  bool _isLoading = true;
  String _errorMsg = "";
  
  late Timer _timer;
  String _timeRemaining = "";

  @override
  void initState() {
    super.initState();
    _fetchPlaylistData();
    _startCountdownTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _updateTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimer());
  }

  void _updateTimer() {
    final now = DateTime.now().toUtc();
    int daysUntilThursday = (DateTime.thursday - now.weekday) % 7;
    if (daysUntilThursday == 0 && (now.hour > 14 || (now.hour == 14 && now.minute >= 30))) {
      daysUntilThursday = 7;
    }
    
    DateTime nextThursday = DateTime.utc(now.year, now.month, now.day).add(Duration(days: daysUntilThursday));
    nextThursday = DateTime.utc(nextThursday.year, nextThursday.month, nextThursday.day, 14, 30);
    
    Duration diff = nextThursday.difference(now);
    if (diff.isNegative) diff = const Duration(seconds: 0);

    int days = diff.inDays;
    int hours = diff.inHours % 24;
    int minutes = diff.inMinutes % 60;
    int seconds = diff.inSeconds % 60;

    if (mounted) {
      setState(() {
        _timeRemaining = "${days}д ${hours}ч ${minutes}м ${seconds}с до смены сезона";
      });
    }
  }

  Future<void> _fetchPlaylistData() async {
    setState(() {
      _isLoading = true;
      _errorMsg = "";
    });

    try {
      final res = await http.get(Uri.parse(PLAYLIST_FEED_URL)).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _playlistData = decoded;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMsg = "Сервер недоступен (Код: ${res.statusCode})";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = "Ошибка сети: проверьте подключение";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Forza6Sniper | Сезон & Советы", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.greenAccent),
            onPressed: _isLoading ? null : _fetchPlaylistData,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : _errorMsg.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMsg, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                        onPressed: _fetchPlaylistData,
                        child: const Text("Повторить", style: TextStyle(color: Colors.black)),
                      )
                    ],
                  ),
                )
              : _buildStructuredView(_playlistData!),
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
      padding: const EdgeInsets.all(14),
      physics: const BouncingScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green.shade900.withOpacity(0.5), const Color(0xFF1E1E1E)]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.greenAccent, size: 26),
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
                    label: Text("SYNCED", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                    backgroundColor: Colors.greenAccent,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )
                ],
              ),
              const Divider(color: Colors.white24, height: 20),
              Row(
                children: [
                  const Icon(Icons.timer, color: Colors.amberAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(_timeRemaining, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
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
    if (carData is Map) {
      name = carData['name']?.toString() ?? "Автомобиль";
      val = carData['est_value']?.toString() ?? "";
    }

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(Icons.directions_car, color: accentColor),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: const Text("Чистый доход с учетом налога аукциона (15%)", style: TextStyle(color: Colors.white38, fontSize: 10)),
        trailing: val.isNotEmpty ? Text(val, style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12)) : null,
      ),
    );
  }
}

// ==========================================
// 2. СКАНЕР АУКЦИОНА С УЧЕТОМ НАЛОГА
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
  final String _currentSlot = "Слот 1 (Авто)";
  final Map<String, List<int>> _observedHistory = {};
  final Map<String, int> _learnedMedians = {};
  int _detectedPrice = 0, _lastNetProfit = 0;
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
      }).catchError((e) {
        debugPrint("Ошибка камеры: $e");
        if (mounted) setState(() => _statusBanner = "Ошибка: Нет доступа к камере");
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
        _lastNetProfit = (median * 0.85).round() - price;
        final discount = ((median - price) / median * 100).round();
        if (discount >= 20 && _lastNetProfit > 150000) {
          _isSnipeAlert = true;
          _statusBanner = "СНАЙП! Чистый доход: +${_lastNetProfit} CR";
          HapticFeedback.heavyImpact();
        } else {
          _isSnipeAlert = false;
          _statusBanner = "Норма (~$median CR). Чистый: +$_lastNetProfit CR";
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
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _statusBanner.contains("Ошибка")
              ? Text(_statusBanner, style: const TextStyle(color: Colors.redAccent))
              : const CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
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
// 3. РАДАР (ПОРТФЕЛЬ С ПЕРЕКЛЮЧЕНИЕМ СТАТУСОВ)
// ==========================================
class WatchlistTab extends StatefulWidget {
  final List<WatchlistItem> portfolio;
  final VoidCallback onUpdate;
  const WatchlistTab({super.key, required this.portfolio, required this.onUpdate});

  @override
  State<WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<WatchlistTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text("Forza6Sniper | Радар"), backgroundColor: const Color(0xFF1E1E1E)),
      body: widget.portfolio.isEmpty
          ? const Center(child: Text("Портфель пуст. Сохраняйте лоты со сканера!", style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              itemCount: widget.portfolio.length,
              itemBuilder: (ctx, i) {
                final item = widget.portfolio[i];
                final netProfit = (item.targetPrice * 0.85).round() - item.buyPrice;
                
                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    title: Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text("Куплено: ${item.buyPrice} CR\nДобавлено: ${item.dateAdded}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("+$netProfit CR", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () {
                            setState(() {
                              item.status = item.status == "HOLD" ? "READY" : "HOLD";
                            });
                            widget.onUpdate();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.status == "READY" ? Colors.green.shade800 : Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.status == "READY" ? "🟢 ГОТОВ К ПРОДАЖЕ" : "🟡 ОТЛЕЖКА",
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

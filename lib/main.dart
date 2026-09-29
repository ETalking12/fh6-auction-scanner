import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

List<CameraDescription> cameras = [];

// Ссылка на манифест наград плейлиста стрима Forza Monthly
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

// Модель элемента радара
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
      final List decoded = jsonDecode(raw);
      setState(() {
        _portfolio = decoded.map((e) => WatchlistItem.fromMap(e)).toList();
      });
    } else {
      // Стартовые ориентиры
      _portfolio = [
        WatchlistItem(
          id: "1",
          name: "Ferrari F80 '25",
          buyPrice: 2100000,
          targetPrice: 20000000,
          status: "HOLD",
          dateAdded: "Сезон завершен 12 дн. назад",
        ),
        WatchlistItem(
          id: "2",
          name: "Toyota Trueno AE86",
          buyPrice: 1400000,
          targetPrice: 6500000,
          status: "SELL",
          dateAdded: "Потолок цены достигнут",
        ),
      ];
      _savePortfolio();
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

    setState(() {
      _portfolio.insert(0, newItem);
    });
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
      WatchlistTab(
        portfolio: _portfolio,
        onUpdate: () => _savePortfolio(),
      ),
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
          BottomNavigationBarItem(icon: Icon(Icons.stream), label: "Стрим & Сезон"),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: "Радар"),
        ],
      ),
    );
  }
}

// ==========================================
// 1. САМООБУЧАЮЩИЙСЯ СКАНЕР С БЫСТРЫМ ЭКСПОРТОМ
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
  final List<String> _slots = ["Слот 1 (Авто)", "Слот 2 (Авто)", "Слот 3 (Авто)"];
  final Map<String, List<int>> _observedHistory = {};
  final Map<String, int> _learnedMedians = {};

  int _detectedPrice = 0;
  int _lastProfit = 0;
  bool _isSnipeAlert = false;
  String _statusBanner = "Листайте лоты для калибровки рыночной нормы";

  @override
  void initState() {
    super.initState();
    _loadMedians();
    _initCamera();
  }

  Future<void> _loadMedians() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("learned_medians_hub");
    if (raw != null) {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      setState(() {
        decoded.forEach((key, val) => _learnedMedians[key] = val as int);
      });
    }
  }

  Future<void> _saveMedians() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("learned_medians_hub", jsonEncode(_learnedMedians));
  }

  void _initCamera() {
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
      if (_controller != null && _controller!.value.isInitialized && !_isProcessing) {
        _captureAndAnalyze();
      }
    }
  }

  Future<void> _captureAndAnalyze() async {
    _isProcessing = true;
    try {
      final XFile photo = await _controller!.takePicture();
      final String rawText = await FlutterTesseractOcr.extractText(
        photo.path,
        language: 'eng',
        args: {"tessedit_char_whitelist": "0123456789,CR "},
      );

      final clean = rawText.replaceAll(',', '').replaceAll(' ', '');
      final match = RegExp(r'(\d{5,9})').firstMatch(clean);

      if (match != null) {
        final price = int.tryParse(match.group(1)!) ?? 0;
        if (price > 10000) {
          _processPrice(price);
        }
      }

      final tmp = File(photo.path);
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {
    } finally {
      _isProcessing = false;
    }
  }

  void _processPrice(int price) {
    if (!_observedHistory.containsKey(_currentSlot)) {
      _observedHistory[_currentSlot] = [];
    }

    final history = _observedHistory[_currentSlot]!;
    if (history.isEmpty || history.last != price) {
      history.add(price);
      if (history.length > 20) history.removeAt(0);
    }

    if (history.length >= 5) {
      final sorted = List<int>.from(history)..sort();
      final median = sorted[sorted.length ~/ 2];
      _learnedMedians[_currentSlot] = median;
      _saveMedians();
    }

    final int? currentMedian = _learnedMedians[_currentSlot];

    setState(() {
      _detectedPrice = price;

      if (currentMedian == null) {
        _isSnipeAlert = false;
        _statusBanner = " Обучение: собрано ${history.length}/5 лотов...";
      } else {
        final netReturn = (currentMedian * 0.85).round(); // налог 15%
        final profit = netReturn - price;
        final discount = ((currentMedian - price) / currentMedian * 100).round();
        _lastProfit = profit;

        if (discount >= 20 && profit > 150000) {
          _isSnipeAlert = true;
          _statusBanner = " СНАЙП! Скидка $discount%! Выгода: +${_formatCR(profit)} CR";
          HapticFeedback.heavyImpact();
        } else if (profit > 0) {
          _isSnipeAlert = false;
          _statusBanner = "Около нормы (~${_formatCR(currentMedian)} CR). Профит: +${_formatCR(profit)} CR";
        } else {
          _isSnipeAlert = false;
          _statusBanner = "Обычная цена (без перепродажной выгоды)";
        }
      }
    });
  }

  String _formatCR(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
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
        body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
      );
    }

    final int? activeMedian = _learnedMedians[_currentSlot];
    final int samplesCount = _observedHistory[_currentSlot]?.length ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),

          // Верхний оверлей
          Positioned(
            top: 45,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<String>(
                    value: _currentSlot,
                    dropdownColor: const Color(0xFF222222),
                    underline: const SizedBox(),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    items: _slots.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _currentSlot = val;
                          _detectedPrice = 0;
                          _isSnipeAlert = false;
                          _statusBanner = "Слот: $val";
                        });
                      }
                    },
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        activeMedian != null ? "Норма: ${_formatCR(activeMedian)} CR" : "Сбор: $samplesCount/5",
                        style: TextStyle(
                          color: activeMedian != null ? Colors.greenAccent : Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        activeMedian != null ? "Обучено ✓" : "Калибровка",
                        style: TextStyle(color: activeMedian != null ? Colors.greenAccent : Colors.grey, fontSize: 10),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),

          // Рамка прицела
          Center(
            child: Container(
              width: 290,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isSnipeAlert ? Colors.greenAccent : Colors.white60,
                  width: _isSnipeAlert ? 3.5 : 2.0,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  color: _isSnipeAlert ? Colors.greenAccent : Colors.black54,
                  child: Text(
                    _isSnipeAlert ? "SNIPE DETECTED!" : "AIM ON BUYOUT",
                    style: TextStyle(
                      color: _isSnipeAlert ? Colors.black : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Нижняя панель с кнопкой быстрого сохранения
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isSnipeAlert ? const Color(0xFF0D3D1E).withOpacity(0.95) : Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _isSnipeAlert ? Colors.greenAccent : Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_statusBanner,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _isSnipeAlert ? Colors.greenAccent : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Лот: ${_detectedPrice > 0 ? '${_formatCR(_detectedPrice)} CR' : '—'}",
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                      Text(
                        "Профит: ${_detectedPrice > 0 && activeMedian != null ? '${_lastProfit > 0 ? '+' : ''}${_formatCR(_lastProfit)} CR' : '—'}",
                        style: TextStyle(
                            color: _isSnipeAlert
                                ? Colors.greenAccent
                                : (_lastProfit > 0 ? Colors.white : Colors.redAccent),
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (_detectedPrice > 0) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add_task, color: Colors.black, size: 18),
                        label: const Text("СОХРАНИТЬ В РАДАР (ПОРТФЕЛЬ)",
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                        onPressed: () => widget.onAddToPortfolio(_currentSlot, _detectedPrice),
                      ),
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

// ========================================================
// 2. МОНИТОРИНГ СТРИМА, ПЛЕЙЛИСТА И КАЛЕНДАРЯ СЕЗОНОВ
// ========================================================
class StrategyAdvisorTab extends StatefulWidget {
  const StrategyAdvisorTab({super.key});

  @override
  State<StrategyAdvisorTab> createState() => _StrategyAdvisorTabState();
}

class _StrategyAdvisorTabState extends State<StrategyAdvisorTab> {
  Timer? _ticker;
  Duration _timeUntilNextSeason = Duration.zero;
  String _currentSeasonName = "Определение...";
  String _currentSeasonKey = "summer";
  Color _seasonColor = Colors.orangeAccent;

  Map<String, dynamic>? _playlistData;
  bool _isLoadingFeed = true;

  @override
  void initState() {
    super.initState();
    _calculateSeasonCountdown();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _calculateSeasonCountdown());
    _fetchPlaylistStreamManifest();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // Расчет сезона Forza Horizon (четверг, 14:30 UTC)
  void _calculateSeasonCountdown() {
    final now = DateTime.now().toUtc();

    // Опорная точка эпохи: Четверг 14:30 UTC (начало Лета)
    final epoch = DateTime.utc(2026, 9, 3, 14, 30);
    final difference = now.difference(epoch);

    final passedWeeks = difference.inDays ~/ 7;
    final seasonIndex = passedWeeks % 4;

    switch (seasonIndex) {
      case 0:
        _currentSeasonName = "ЛЕТО (Summer)";
        _currentSeasonKey = "summer";
        _seasonColor = Colors.amberAccent;
        break;
      case 1:
        _currentSeasonName = "ОСЕНЬ (Autumn)";
        _currentSeasonKey = "autumn";
        _seasonColor = Colors.orangeAccent;
        break;
      case 2:
        _currentSeasonName = "ЗИМА (Winter)";
        _currentSeasonKey = "winter";
        _seasonColor = Colors.lightBlueAccent;
        break;
      default:
        _currentSeasonName = "ВЕСНА (Spring)";
        _currentSeasonKey = "spring";
        _seasonColor = Colors.greenAccent;
        break;
    }

    // Расчет времени до ближайшего четверга 14:30 UTC
    int daysUntilThursday = (DateTime.thursday - now.weekday) % 7;
    DateTime nextThursday = DateTime.utc(now.year, now.month, now.day + daysUntilThursday, 14, 30);

    if (now.isAfter(nextThursday)) {
      nextThursday = nextThursday.add(const Duration(days: 7));
    }

    if (mounted) {
      setState(() {
        _timeUntilNextSeason = nextThursday.difference(now);
      });
    }
  }

  // Загрузка манифеста плейлиста стрима Forza Monthly
  Future<void> _fetchPlaylistStreamManifest() async {
    try {
      final res = await http.get(Uri.parse(PLAYLIST_FEED_URL)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        setState(() {
          _playlistData = jsonDecode(res.body);
          _isLoadingFeed = false;
        });
        return;
      }
    } catch (_) {}
    setState(() => _isLoadingFeed = false);
  }

  String _formatDuration(Duration d) {
    int days = d.inDays;
    int hours = d.inHours % 24;
    int mins = d.inMinutes % 60;
    int secs = d.inSeconds % 60;
    return "${days}д ${hours}ч ${mins}м ${secs}с";
  }

  @override
  Widget build(BuildContext context) {
    final rewardData = _playlistData?["rewards"]?[_currentSeasonKey];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Монитор плейлиста и сезона", style: TextStyle(fontSize: 17)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.greenAccent),
            onPressed: () {
              setState(() => _isLoadingFeed = true);
              _fetchPlaylistStreamManifest();
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Карточка сезона с живым таймером
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_seasonColor.withOpacity(0.25), const Color(0xFF1E1E1E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _seasonColor.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_currentSeasonName,
                          style: TextStyle(color: _seasonColor, fontSize: 18, fontWeight: FontWeight.bold)),
                      const Icon(Icons.timer_outlined, color: Colors.white70),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text("До смены сезона: ${_formatDuration(_timeUntilNextSeason)}",
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text("Смена цикла: каждый четверг в 17:30 / 18:30 МСК",
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Карточка данных со стрима Forza Monthly
            const Text("НАГРАДЫ ПЛЕЙЛИСТА (ИЗ СТРИМА):",
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: _isLoadingFeed
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                  : rewardData != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.live_tv, color: Colors.redAccent, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  "Серия ${_playlistData?['series_number'] ?? '39'} • ${_playlistData?['stream_source'] ?? 'Forza Monthly'}",
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 16),
                            Text("🥇 Эксклюзив 20 очков: ${rewardData['car_20pts']}",
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("🥈 Эксклюзив 40 очков: ${rewardData['car_40pts']}",
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                "Тактика: Скупайте ${rewardData['car_20pts']} по цене выкупа до ${(rewardData['target_buyout'] / 1000000).toStringAsFixed(1)}M CR. Через 3 недели перепродадите за 20M.",
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                              ),
                            )
                          ],
                        )
                      : const Text("Манифест оффлайн. Включите Wi-Fi/4G для обновления плейлиста.",
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),

            const SizedBox(height: 16),

            // Советник по дням недели
            const Text("СТРАТЕГИЯ СЕГОДНЯ:",
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Охота на недельный сброс",
                      style: TextStyle(color: Colors.blueAccent, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    "Игроки завершают еженедельные чемпионаты. Снайпите призовые новинки на дне цен и не выставляйте их на продажу раньше, чем через 15 дней после закрытия сезона.",
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. РАДАР (ПОРТФЕЛЬ ИНВЕСТИЦИЙ)
// ==========================================
class WatchlistTab extends StatelessWidget {
  final List<WatchlistItem> portfolio;
  final VoidCallback onUpdate;

  const WatchlistTab({super.key, required this.portfolio, required this.onUpdate});

  String _formatCR(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Радар и портфель снайпера", style: TextStyle(fontSize: 17)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: portfolio.isEmpty
          ? const Center(
              child: Text("Портфель пуст.\nСохраняйте лоты прямо со Сканера!",
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: portfolio.length,
              itemBuilder: (ctx, i) {
                final item = portfolio[i];
                final netSell = (item.targetPrice * 0.85).round();
                final profit = netSell - item.buyPrice;

                Color statusColor = Colors.orangeAccent;
                String statusTitle = "ДЕРЖАТЬ";
                if (item.status == "SELL") {
                  statusColor = Colors.greenAccent;
                  statusTitle = "ПРОДАВАТЬ (ПИК)";
                }

                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item.name,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: statusColor)),
                              child: Text(statusTitle,
                                  style: TextStyle(
                                      color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(item.dateAdded, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        const Divider(color: Colors.white12, height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Куплено: ${_formatCR(item.buyPrice)} CR",
                                style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            Text("Цель: ${_formatCR(item.targetPrice)} CR",
                                style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            Text("+${_formatCR(profit)} CR",
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

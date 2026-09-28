import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Камеры не найдены: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FH6AuctionHubApp(),
  ));
}

class FH6AuctionHubApp extends StatefulWidget {
  const FH6AuctionHubApp({super.key});

  @override
  State<FH6AuctionHubApp> createState() => _FH6AuctionHubAppState();
}

class _FH6AuctionHubAppState extends State<FH6AuctionHubApp> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const ScannerTab(),
    const StrategyAdvisorTab(),
    const WatchlistTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF181818),
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            activeIcon: Icon(Icons.camera_alt),
            label: "Сканер",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline),
            activeIcon: Icon(Icons.lightbulb),
            label: "Советник",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.track_changes_outlined),
            activeIcon: Icon(Icons.track_changes),
            label: "Радар",
          ),
        ],
      ),
    );
  }
}

// ==========================================
// ВКЛАДКА 1: САМООБУЧАЮЩИЙСЯ СКАНЕР КАМЕРЫ
// ==========================================
class ScannerTab extends StatefulWidget {
  const ScannerTab({super.key});

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
  String _statusBanner = "Листайте лоты на мониторе для калибровки нормы";

  @override
  void initState() {
    super.initState();
    _loadStoredMedians();
    _initCamera();
  }

  Future<void> _loadStoredMedians() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("learned_medians_hub");
    if (raw != null) {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      setState(() {
        decoded.forEach((key, val) => _learnedMedians[key] = val as int);
      });
    }
  }

  Future<void> _persistMedians() async {
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
          _processIncomingPrice(price);
        }
      }

      final tmp = File(photo.path);
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {
    } finally {
      _isProcessing = false;
    }
  }

  void _processIncomingPrice(int price) {
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
      _persistMedians();
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
          _statusBanner = " СНАЙП! Скидка $discount%! Чистыми: +${_formatCR(profit)} CR";
          HapticFeedback.heavyImpact();
        } else if (profit > 0) {
          _isSnipeAlert = false;
          _statusBanner = "Норма (~${_formatCR(currentMedian)} CR). Профит мал: +${_formatCR(profit)} CR";
        } else {
          _isSnipeAlert = false;
          _statusBanner = "Обычная цена лота (выше нормы перепродажи)";
        }
      }
    });
  }

  void _resetCurrentSlot() {
    setState(() {
      _observedHistory[_currentSlot]?.clear();
      _learnedMedians.remove(_currentSlot);
      _detectedPrice = 0;
      _isSnipeAlert = false;
      _statusBanner = "Память слота сброшена. Листайте для переобучения.";
    });
    _persistMedians();
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

          // Верхний оверлей управления
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
              child: Column(
                children: [
                  Row(
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
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        tooltip: "Сбросить память",
                        onPressed: _resetCurrentSlot,
                      )
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        activeMedian != null
                            ? "Рынок: ${_formatCR(activeMedian)} CR"
                            : "Сбор базы ($samplesCount/5)",
                        style: TextStyle(
                          color: activeMedian != null ? Colors.greenAccent : Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        activeMedian != null ? "Обучено ✓" : "Калибровка",
                        style: TextStyle(color: activeMedian != null ? Colors.greenAccent : Colors.grey, fontSize: 11),
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

          // Нижняя панель
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
                  Text(_statusBanner, textAlign: TextAlign.center, style: TextStyle(color: _isSnipeAlert ? Colors.greenAccent : Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("В фокусе: ${_detectedPrice > 0 ? '${_formatCR(_detectedPrice)} CR' : '—'}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                      Text(
                        "Профит: ${_detectedPrice > 0 && activeMedian != null ? '${_lastProfit > 0 ? '+' : ''}${_formatCR(_lastProfit)} CR' : '—'}",
                        style: TextStyle(color: _isSnipeAlert ? Colors.greenAccent : (_lastProfit > 0 ? Colors.white : Colors.redAccent), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
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
// ВКЛАДКА 2: СОВЕТНИК ПО СТРАТЕГИЯМ СЛЕЖЕНИЯ
// ==========================================
class StrategyAdvisorTab extends StatelessWidget {
  const StrategyAdvisorTab({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isWeekend = now.weekday >= 4 && now.weekday <= 6; // Четверг-суббота (смена сезона)

    final List<Map<String, dynamic>> tips = [
      {
        "title": isWeekend ? "Сезонный сброс (Thursday-Weekend Flood)" : "Фаза стабилизации цен (Середина недели)",
        "badge": "СЕЗОННЫЙ ЦИКЛ",
        "color": Colors.blueAccent,
        "text": isWeekend
            ? "Сейчас игроки массово закрывают плейлист и сливают призовые дубликаты. Выставляйте фильтр выкупа на 1.2–2.5M CR. Ловите свежие фестивальные эксклюзивы на абсолютном дне цены."
            : "Первичный наплыв лотов спал. Предложений меньше, игра начинает поднимать динамическую планку выкупа. Переходите к точечному снайпингу редких моделей.",
        "targets": "Эксклюзивы за 20/40 очков сезона • Призовые авто серии",
      },
      {
        "title": "Золотой фонд ликвидности (20M CR Anchor)",
        "badge": "БЫСТРЫЙ КЭШ",
        "color": Colors.greenAccent,
        "text": "Машины, которые раскупаются за 1–3 минуты по максимальной цене 20M CR. Если видите такой лот с выкупом до 11M — забирайте моментально. Гарантированный профит +6–8M чистыми.",
        "targets": "Toyota Trueno AE86 • Ferrari F80 '25 • Subaru 22B STi • Lexus LFA",
      },
      {
        "title": "Всплеск под командный Триал (Weekly Trial Meta)",
        "badge": "ИМПУЛЬСНЫЙ СПРОС",
        "color": Colors.orangeAccent,
        "text": "Большинство игроков не умеют тюнить под ограничения Триала и покупают готовые мета-машины по завышенным ценам. Наценка при перепродаже составляет +50–80%.",
        "targets": "Ford GT '05 (S1) • Honda NSX-R '92 (A800) • Mitsubishi Evo VI",
      },
      {
        "title": "Зона риска: угроза рерана (Rerun Crash Warning)",
        "badge": "ВЫСОКИЙ РИСК",
        "color": Colors.redAccent,
        "text": "Машины, которые не появлялись в плейлистах более 5–7 месяцев. Разработчики могут вернуть их в Forzathon в любой момент, обрушив цену с 20M до 2M. Не копите их на складе!",
        "targets": "Ferrari SF90 Stradale • McLaren 765LT • Porsche Mission R",
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Стратегии и советы слежения", style: TextStyle(fontSize: 17)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: tips.length,
        itemBuilder: (ctx, i) {
          final t = tips[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (t["color"] as Color).withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (t["color"] as Color).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(t["badge"], style: TextStyle(color: t["color"], fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const Icon(Icons.bolt, color: Colors.white24, size: 18),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t["title"], style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(t["text"], style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(6)),
                  child: Text("🎯 Цели: ${t['targets']}", style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// ВКЛАДКА 3: РАДАР И ПОРТФЕЛЬ ИНВЕСТИЦИЙ
// ==========================================
class WatchlistTab extends StatefulWidget {
  const WatchlistTab({super.key});

  @override
  State<WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<WatchlistTab> {
  final List<Map<String, dynamic>> _items = [
    {
      "name": "Ferrari F80 '25",
      "buy": 2100000,
      "target": 20000000,
      "status": "HOLD",
      "note": "Сезон завершён. Алгоритм игры плавно тянет цену к 20M."
    },
    {
      "name": "Toyota Trueno AE86",
      "buy": 1500000,
      "target": 6500000,
      "status": "SELL",
      "note": "Выкуп на стабильном потолке. Пора сливать."
    },
    {
      "name": "Hyundai N Vision 74",
      "buy": 1200000,
      "target": 16000000,
      "status": "BUY",
      "note": "Текущая награда сезона! Скупайте все дешевые лоты."
    },
  ];

  String _formatCR(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  void _addNewCarDialog() {
    String name = "";
    int buy = 0;
    int target = 20000000;
    String status = "BUY";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Добавить цель на радар", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Модель авто", labelStyle: TextStyle(color: Colors.grey)),
              onChanged: (v) => name = v,
            ),
            TextField(
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Цена закупки (CR)", labelStyle: TextStyle(color: Colors.grey)),
              onChanged: (v) => buy = int.tryParse(v) ?? 0,
            ),
            TextField(
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Цель продажи (CR)", labelStyle: TextStyle(color: Colors.grey)),
              onChanged: (v) => target = int.tryParse(v) ?? 20000000,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
            onPressed: () {
              if (name.isNotEmpty) {
                setState(() {
                  _items.add({
                    "name": name,
                    "buy": buy,
                    "target": target,
                    "status": status,
                    "note": "Добавлено пользователем"
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Добавить", style: TextStyle(color: Colors.black)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Инвестиционный радар", style: TextStyle(fontSize: 17)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.add, color: Colors.greenAccent), onPressed: _addNewCarDialog),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (ctx, i) {
          final item = _items[i];
          final netRevenue = ((item["target"] as int) * 0.85).round();
          final profit = netRevenue - (item["buy"] as int);

          Color statusColor = Colors.blueAccent;
          String statusTitle = "СКУПКА";
          if (item["status"] == "HOLD") {
            statusColor = Colors.orangeAccent;
            statusTitle = "ДЕРЖАТЬ";
          } else if (item["status"] == "SELL") {
            statusColor = Colors.greenAccent;
            statusTitle = "ПРОДАВАТЬ";
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
                      Expanded(
                        child: Text(item["name"], style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(5), border: Border.all(color: statusColor)),
                        child: Text(statusTitle, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item["note"], style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const Divider(color: Colors.white12, height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Куплено: ${_formatCR(item['buy'])} CR", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      Text("Цель: ${_formatCR(item['target'])} CR", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      Text("+${_formatCR(profit)} CR", style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
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

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
  String status;
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
// 1. АВТОМАТИЧЕСКИЙ СЕЗОННЫЙ СОВЕТНИК
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

  void _showCarDetails(BuildContext context, String carName, String estValue, String season) {
    const String imageUrl = "https://images.unsplash.com/photo-1503376780353-7e6692767b70?auto=format&fit=crop&w=800&q=80";

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.greenAccent, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.95)],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.darken,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF1E1E1E)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_car, color: Colors.greenAccent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(carName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 20),
                      _buildSpecRow("Сезон награды:", season),
                      _buildSpecRow("Рыночный потолок:", estValue),
                      _buildSpecRow("Рекомендуемый класс:", "S1 900 / S2 998"),
                      _buildSpecRow("Тип привода:", "Полный (AWD) / Задний"),
                      _buildSpecRow("Ликвидность:", "🔥 Дефицит (Топ)"),
                      const SizedBox(height: 12),
                      const Text(
                        "💡 Совет по снайпингу: Модель пользуется повышенным спросом в текущей серии «Британский Автопром». Скупайте лоты со скидкой от 20% и выставляйте по максимальной цене.",
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("ЗАКРЫТЬ", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
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
          ...cars20.map((c) => _buildCarCard(context, c, Colors.amberAccent, season)),
          const SizedBox(height: 12),
        ],

        if (cars40.isNotEmpty) ...[
          const Text("⭐ НАГРАДЫ 40 PTS", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...cars40.map((c) => _buildCarCard(context, c, Colors.cyanAccent, season)),
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

  Widget _buildCarCard(BuildContext context, dynamic carData, Color accentColor, String activeSeason) {
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
        onTap: () => _showCarDetails(context, name, val, activeSeason),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(Icons.directions_car, color: accentColor),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: const Text("Тапните для просмотра характеристик", style: TextStyle(color: Colors.white38, fontSize: 10)),
        trailing: val.isNotEmpty ? Text(val, style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12)) : null,
      ),
    );
  }
}

// ==========================================
// 2. СКАНЕР АУКЦИОНА СТАБИЛЬНЫЙ
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
  bool _isTorchOn = false; // Фонарик выключен по умолчанию
  
  final String _currentSlot = "Слот 1 (Авто)";
  int _detectedPrice = 0;
  bool _isSnipeAlert = false;
  String _lastRawText = "Инициализация...";
  String _statusBanner = "Наведите рамку на цены выкупа";

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.low, enableAudio: false);
    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off); // Принудительно выключаем вспышку
      if (!mounted) return;
      setState(() {});
      _isScanning = true;
      _startScanLoop();
    } catch (e) {
      debugPrint("Ошибка камеры: $e");
      if (mounted) setState(() => _statusBanner = "Ошибка камеры: $e");
    }
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      setState(() => _isTorchOn = !_isTorchOn);
      await _controller!.setFlashMode(_isTorchOn ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      debugPrint("Ошибка фонарика: $e");
    }
  }

  void _startScanLoop() async {
    while (_isScanning && mounted) {
      if (_controller != null && _controller!.value.isInitialized && !_isProcessing) {
        _isProcessing = true;
        try {
          final image = await _controller!.takePicture();
          
          if (!mounted) break;
          setState(() => _lastRawText = "Анализ кадра...");

          final text = await FlutterTesseractOcr.extractText(
            image.path,
            language: 'eng',
            args: {"tessedit_char_whitelist": "0123456789,CR "}
          );

          if (!mounted) break;
          
          final cleanedView = text.trim().replaceAll('\n', ' ');
          setState(() {
            _lastRawText = cleanedView.isEmpty ? "Текст не найден" : cleanedView;
          });

          final cleanNumbers = text.replaceAll(RegExp(r'[^0-9]'), '');
          final match = RegExp(r'\d{6,8}').firstMatch(cleanNumbers);
          
          if (match != null) {
            int foundPrice = int.parse(match.group(0)!);
            _processPrice(foundPrice);
          }
        } catch (e) {
          debugPrint("Ошибка OCR: $e");
          if (mounted) {
            setState(() => _lastRawText = "Ждем кадр...");
          }
        } finally {
          _isProcessing = false;
        }
      }
      // Увеличенная пауза (2.5 сек) для защиты от перегрузки памяти и зависаний
      await Future.delayed(const Duration(milliseconds: 2500));
    }
  }

  void _processPrice(int price) {
    if (price < 100000 || !mounted) return;

    setState(() {
      _detectedPrice = price;
      if (price <= 6000000) {
        _isSnipeAlert = true;
        _statusBanner = "🔥 СНАЙП! Найдена низкая цена: $price CR";
        HapticFeedback.heavyImpact();
      } else {
        _isSnipeAlert = false;
        _statusBanner = "Цена: $price CR (Обычная)";
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
          
          // Кнопка ручного включения/выключения фонарика в правом верхнем углу
          Positioned(
            top: 45, right: 20,
            child: FloatingActionButton.small(
              backgroundColor: _isTorchOn ? Colors.amberAccent : Colors.black54,
              onPressed: _toggleTorch,
              child: Icon(
                _isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: _isTorchOn ? Colors.black : Colors.white,
              ),
            ),
          ),

          // Рамка сканирования
          Center(
            child: Container(
              width: 330, height: 130,
              decoration: BoxDecoration(
                  border: Border.all(
                    color: _isSnipeAlert ? Colors.greenAccent : Colors.white70,
                    width: _isSnipeAlert ? 4.0 : 2.5,
                  ),
                  boxShadow: _isSnipeAlert
                      ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 12, spreadRadius: 3)]
                      : [],
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          
          // Нижняя панель с отладкой
          Positioned(
            bottom: 20, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _isSnipeAlert ? Colors.greenAccent : Colors.white24, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.remove_red_eye, color: Colors.greenAccent, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "OCR видит: $_lastRawText",
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 14),
                  Text(
                    _statusBanner,
                    style: TextStyle(
                      color: _isSnipeAlert ? Colors.greenAccent : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (_detectedPrice > 0) ...[
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                      onPressed: () => widget.onAddToPortfolio(_currentSlot, _detectedPrice),
                      child: const Text("СОХРАНИТЬ В РАДАР", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
// 3. РАДАР (ПОРТФЕЛЬ)
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

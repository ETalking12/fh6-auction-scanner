import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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
  String name;
  int buyPrice;
  int targetPrice;     
  int projectedPrice;  
  String status;
  final String dateAdded;

  WatchlistItem({
    required this.id, required this.name, required this.buyPrice,
    required this.targetPrice, required this.projectedPrice, 
    required this.status, required this.dateAdded,
  });

  Map<String, dynamic> toMap() => {
        "id": id, "name": name, "buyPrice": buyPrice,
        "targetPrice": targetPrice, "projectedPrice": projectedPrice,
        "status": status, "dateAdded": dateAdded,
      };

  factory WatchlistItem.fromMap(Map<String, dynamic> map) => WatchlistItem(
        id: map["id"]?.toString() ?? "",
        name: map["name"]?.toString() ?? "Неизвестно",
        buyPrice: (map["buyPrice"] as num?)?.toInt() ?? 0,
        targetPrice: (map["targetPrice"] as num?)?.toInt() ?? 20000000,
        projectedPrice: (map["projectedPrice"] as num?)?.toInt() ?? 20000000,
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

  void _addQuickSnipeToPortfolio(String carName, int buyPrice, int currentMarket, int projectedValue) {
    final newItem = WatchlistItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: carName, buyPrice: buyPrice, targetPrice: currentMarket,
      projectedPrice: projectedValue, status: "HOLD", 
      dateAdded: "${DateTime.now().day}.${DateTime.now().month}",
    );
    setState(() => _portfolio.insert(0, newItem));
    _savePortfolio();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✓ Активы обновлены: $carName"), backgroundColor: Colors.green[800], duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ScannerTab(onAddToPortfolio: _addQuickSnipeToPortfolio),
      const StrategyAdvisorTab(),
      const PriceDatabaseTab(),
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
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: "Аналитика"),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "База Цен"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "Радар"),
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
    setState(() { _isLoading = true; _errorMsg = ""; });
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
                        "💡 Совет по снайпингу: Модель пользуется повышенным спросом в текущей серии. Скупайте лоты со скидкой и выставляйте по максимальной цене.",
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
// 2. СКАНЕР АУКЦИОНА
// ==========================================
class ScannerTab extends StatefulWidget {
  final Function(String name, int price, int marketPrice, int projectedPrice) onAddToPortfolio;
  const ScannerTab({super.key, required this.onAddToPortfolio});
  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  CameraController? _controller;
  final TextRecognizer _textRecognizer = TextRecognizer();
  bool _isProcessing = false;
  bool _isScanning = false;
  bool _isTorchOn = false;
  
  int _targetMarketValue = 20000000;
  double _desiredDiscount = 0.30; 
  
  int _detectedPrice = 0;
  String _detectedCarName = "";
  bool _isSnipeAlert = false;
  String _lastRawText = "Готов к сканированию...";
  String _statusBanner = "Наведите рамку на цены выкупа";

  @override
  void initState() {
    super.initState();
    _loadCalibration();
    _initCamera();
  }

  Future<void> _loadCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _targetMarketValue = prefs.getInt("snipe_market_value") ?? 20000000;
      _desiredDiscount = prefs.getDouble("snipe_discount") ?? 0.30;
    });
  }

  Future<void> _saveCalibration(int value, double discount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("snipe_market_value", value);
    await prefs.setDouble("snipe_discount", discount);
    setState(() { _targetMarketValue = value; _desiredDiscount = discount; });
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off);
      if (!mounted) return;
      setState(() {});
      _isScanning = true;
      _startScanLoop();
    } catch (e) {
      if (mounted) setState(() => _statusBanner = "Ошибка камеры: $e");
    }
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isTorchOn = !_isTorchOn);
    await _controller!.setFlashMode(_isTorchOn ? FlashMode.torch : FlashMode.off);
  }

  void _startScanLoop() async {
    while (_isScanning && mounted) {
      if (_controller != null && _controller!.value.isInitialized && !_isProcessing) {
        _isProcessing = true;
        try {
          final image = await _controller!.takePicture();
          if (!mounted) break;
          final inputImage = InputImage.fromFilePath(image.path);
          final recognizedText = await _textRecognizer.processImage(inputImage);
          if (!mounted) break;

          double maxY = 1.0;
          for (TextBlock block in recognizedText.blocks) {
            if (block.boundingBox.bottom > maxY) maxY = block.boundingBox.bottom;
          }

          String focusedText = "";
          for (TextBlock block in recognizedText.blocks) {
            double blockCenterY = block.boundingBox.top + (block.boundingBox.height / 2);
            if (blockCenterY > (maxY * 0.35) && blockCenterY < (maxY * 0.65)) {
              focusedText += block.text + " ";
            }
          }

          final raw = focusedText.trim();
          setState(() {
            _lastRawText = raw.isEmpty ? "Пусто в рамке" : (raw.length > 35 ? "${raw.substring(0, 35)}..." : raw.replaceAll('\n', ' '));
          });

          final priceRegex = RegExp(r'\b\d{1,3}(?:[., ]\d{3})*\b|\b\d+\b');
          final priceMatches = priceRegex.allMatches(raw);
          List<int> validPrices = [];
          for (final match in priceMatches) {
            String cleanNumStr = match.group(0)!.replaceAll(RegExp(r'[^0-9]'), '');
            if (cleanNumStr.isNotEmpty) {
              int parsedNum = int.parse(cleanNumStr);
              if (parsedNum >= 10000 && parsedNum <= 20000000) validPrices.add(parsedNum);
            }
          }

          final wordRegex = RegExp(r'\b[A-Za-zА-Яа-я0-9]{2,15}\b');
          final wordMatches = wordRegex.allMatches(raw);
          List<String> validWords = [];
          for (final m in wordMatches) {
            String word = m.group(0)!;
            String upper = word.toUpperCase();
            if (upper == "MIN" || upper == "МИН" || upper == "CR") continue;
            if (RegExp(r'^\d+$').hasMatch(word)) {
              int val = int.parse(word);
              if (!((val >= 1900 && val <= 2050) || word.length == 3)) continue;
            }
            validWords.add(word);
          }

          String guessedName = validWords.take(4).join(" ");
          if (guessedName.isNotEmpty) _detectedCarName = guessedName;

          if (validPrices.isNotEmpty) {
            int minPrice = validPrices.reduce((curr, next) => curr < next ? curr : next);
            _processPrice(minPrice);
          } else {
            if (mounted) setState(() { _detectedPrice = 0; _isSnipeAlert = false; _statusBanner = "Наведите рамку на цены выкупа"; });
          }
        } catch (e) {
          if (mounted) setState(() => _lastRawText = "Ошибка распознавания");
        } finally {
          _isProcessing = false;
        }
      }
      await Future.delayed(const Duration(milliseconds: 1200));
    }
  }

  void _processPrice(int price) {
    if (price < 10000 || !mounted) return;
    int alertThreshold = (_targetMarketValue * (1 - _desiredDiscount)).round();
    setState(() {
      _detectedPrice = price;
      if (price <= alertThreshold) {
        _isSnipeAlert = true;
        _statusBanner = "🔥 СНАЙП! Цена: $price CR (Выгода > ${(_desiredDiscount * 100).toInt()}%)";
        HapticFeedback.heavyImpact();
      } else {
        _isSnipeAlert = false;
        _statusBanner = "Цена: $price CR (Маржинальность мала)";
      }
    });
  }

  void _showCalibrationDialog() {
    final valController = TextEditingController(text: _targetMarketValue.toString());
    double tempDiscount = _desiredDiscount;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateBuilder) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Параметры закупки", style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Укажите текущую среднюю стоимость лота на рынке:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 10),
                TextField(
                  controller: valController, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Текущая рыночная цена (CR)", labelStyle: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(height: 20),
                Text("Желаемая скидка от рынка: ${(tempDiscount * 100).toInt()}%", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                Slider(
                  value: tempDiscount, min: 0.05, max: 0.90, divisions: 17,
                  activeColor: Colors.greenAccent, inactiveColor: Colors.white24,
                  onChanged: (val) => setStateBuilder(() => tempDiscount = val),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.white54))),
              TextButton(
                onPressed: () {
                  int newVal = int.tryParse(valController.text) ?? 20000000;
                  _saveCalibration(newVal, tempDiscount);
                  Navigator.pop(ctx);
                },
                child: const Text("ПРИМЕНИТЬ", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showSaveDialog(int currentPrice, String guessedName) {
    final nameController = TextEditingController(text: guessedName);
    final priceController = TextEditingController(text: currentPrice.toString());
    final marketPriceController = TextEditingController(text: _targetMarketValue.toString());
    final projectedController = TextEditingController(text: "20000000"); 

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Принять на баланс", style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController, style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Наименование лота", labelStyle: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceController, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Фактическая цена покупки (CR)", labelStyle: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: marketPriceController, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Рыночная цена СЕЙЧАС (CR)", labelStyle: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: projectedController, style: const TextStyle(color: Colors.amberAccent), keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Прогноз стоимости (МАКСИМУМ)", labelStyle: TextStyle(color: Colors.amberAccent)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              String name = nameController.text.trim();
              if (name.isEmpty) name = "Неизвестная машина";
              int price = int.tryParse(priceController.text) ?? currentPrice;
              int market = int.tryParse(marketPriceController.text) ?? _targetMarketValue;
              int projected = int.tryParse(projectedController.text) ?? 20000000;
              
              widget.onAddToPortfolio(name, price, market, projected);
              Navigator.pop(ctx);
            },
            child: const Text("В РАДАР", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isScanning = false;
    _textRecognizer.close();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(backgroundColor: Colors.black, body: Center(child: Text(_statusBanner, style: const TextStyle(color: Colors.redAccent))));
    }
    
    int alertThreshold = (_targetMarketValue * (1 - _desiredDiscount)).round();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          Positioned(
            top: 45, right: 20,
            child: FloatingActionButton.small(
              heroTag: "btn1", backgroundColor: _isTorchOn ? Colors.amberAccent : Colors.black54,
              onPressed: _toggleTorch, child: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: _isTorchOn ? Colors.black : Colors.white),
            ),
          ),
          Positioned(
            top: 45, left: 20,
            child: FloatingActionButton.extended(
              heroTag: "btn2", backgroundColor: Colors.black54, onPressed: _showCalibrationDialog,
              icon: const Icon(Icons.tune, color: Colors.greenAccent, size: 18),
              label: Text("Сигнал < $alertThreshold", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          Center(
            child: Container(
              width: 330, height: 130,
              decoration: BoxDecoration(
                  border: Border.all(color: _isSnipeAlert ? Colors.greenAccent : Colors.white70, width: _isSnipeAlert ? 4.0 : 2.5),
                  boxShadow: _isSnipeAlert ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 12, spreadRadius: 3)] : [],
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Positioned(
            bottom: 20, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.9), borderRadius: BorderRadius.circular(14), border: Border.all(color: _isSnipeAlert ? Colors.greenAccent : Colors.white24, width: 1.5)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("OCR видит (в рамке): $_lastRawText", style: const TextStyle(color: Colors.white60, fontSize: 11), overflow: TextOverflow.ellipsis),
                  const Divider(color: Colors.white24, height: 14),
                  Text(_statusBanner, style: TextStyle(color: _isSnipeAlert ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  if (_detectedPrice > 0) ...[
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                      onPressed: () => _showSaveDialog(_detectedPrice, _detectedCarName),
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
// 3. БАЗА ЦЕН С ФИНАЛЬНЫМ ЧИСТЯЩИМ ПАРСЕРОМ
// ==========================================
class PriceDatabaseTab extends StatefulWidget {
  const PriceDatabaseTab({super.key});

  @override
  State<PriceDatabaseTab> createState() => _PriceDatabaseTabState();
}

class _PriceDatabaseTabState extends State<PriceDatabaseTab> {
  final String _publicDataSourceUrl = 
      "https://docs.google.com/spreadsheets/d/1GvM6Q5PD9UH5QxWI2VSMxWiTFkR4RShc/export?format=csv";

  List<dynamic> _allCars = [];
  List<dynamic> _filteredCars = [];
  bool _isLoading = true;
  String _errorMsg = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMarketData();
    _searchController.addListener(_filterCars);
  }

  Future<void> _fetchMarketData() async {
    setState(() {
      _isLoading = true;
      _errorMsg = "";
    });

    try {
      final res = await http.get(Uri.parse(_publicDataSourceUrl)).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (res.statusCode == 200) {
        final bodyString = utf8.decode(res.bodyBytes);
        List<dynamic> parsedData = [];

        List<String> lines = const LineSplitter().convert(bodyString);
        String lastKnownBrand = ""; 

        // Пропускаем шапку таблицы (начинаем с i = 1)
        for (int i = 1; i < lines.length; i++) {
          // Используем обычный сплит по запятым
          List<String> parts = lines[i].split(',');
          
          if (parts.length >= 4) {
            String colBrand = parts[1].replaceAll('"', '').trim();
            if (colBrand.isNotEmpty) {
              lastKnownBrand = colBrand; // Память для объединенных ячеек (например Abarth)
            }
            
            String brand = lastKnownBrand;
            String model = parts[3].replaceAll('"', '').trim();

            if (model.isNotEmpty) {
              // Собираем весь "хвост" строки после модели
              List<String> tail = [];
              for (int j = 4; j < parts.length; j++) {
                String p = parts[j].replaceAll('"', '').trim();
                if (p.isNotEmpty) tail.add(p);
              }

              // 1. Очистка от системного мусора в конце (TRUE/FALSE)
              while (tail.isNotEmpty && 
                    (tail.last.toUpperCase() == 'TRUE' || tail.last.toUpperCase() == 'FALSE')) {
                tail.removeLast();
              }

              String price = "0";
              String carClass = "";
              String source = "";

              if (tail.isNotEmpty) {
                // 2. Ищем цену (число от 10 и выше в самом конце строки)
                String lastEl = tail.last;
                String digitsOnly = lastEl.replaceAll(RegExp(r'[^0-9]'), '');
                if (digitsOnly.isNotEmpty && digitsOnly == lastEl && int.tryParse(digitsOnly) != null && int.parse(digitsOnly) > 10) {
                  price = digitsOnly;
                  tail.removeLast(); // Удаляем цену, чтобы не попала в статус
                }
                
                // 3. Убираем короткие системные цифры (например, '2', '3', '10') в начале хвоста
                if (tail.isNotEmpty && RegExp(r'^\d{1,2}$').hasMatch(tail.first)) {
                  tail.removeAt(0);
                }

                // 4. Оставшийся первый элемент - это Класс (например, D 100)
                if (tail.isNotEmpty) {
                  carClass = tail.first;
                  tail.removeAt(0); // Удаляем класс из хвоста
                }
                
                // 5. Всё, что осталось (включая разорванные запятыми слова) - это Источник
                if (tail.isNotEmpty) {
                  source = tail.join(', ');
                }
              }

              parsedData.add({
                "name": "$brand $model".trim(),
                "price": price.isEmpty ? "0" : price,
                "status": "$carClass${source.isNotEmpty ? ' • $source' : ''}".trim(),
              });
            }
          }
        }

        setState(() {
          _allCars = parsedData;
          _filteredCars = parsedData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMsg = "Не удалось загрузить базу (Код: ${res.statusCode})";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = "Нет связи с источником данных";
        _isLoading = false;
      });
    }
  }

  void _filterCars() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCars = _allCars;
      } else {
        _filteredCars = _allCars.where((car) {
          final name = car['name']?.toString().toLowerCase() ?? "";
          return name.contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildTrendIndicator(String status) {
    Color color = Colors.greenAccent;
    IconData icon = Icons.info_outline;
    String lowerStatus = status.toLowerCase();

    if (lowerStatus.contains("seasonal") || lowerStatus.contains("сезон")) {
      color = Colors.amberAccent;
      icon = Icons.star;
    } else if (lowerStatus.contains("wheelspin") || lowerStatus.contains("рулетка")) {
      color = Colors.purpleAccent;
      icon = Icons.casino;
    } else if (lowerStatus.contains("autoshow") || lowerStatus.contains("автосалон")) {
      color = Colors.white54;
      icon = Icons.storefront;
    } else if (lowerStatus.contains("dlc") || lowerStatus.contains("car pass") || lowerStatus.contains("包")) {
      color = Colors.lightBlueAccent;
      icon = Icons.card_giftcard;
    } else if (lowerStatus.contains("collection") || lowerStatus.contains("коллекци")) {
      color = Colors.pinkAccent;
      icon = Icons.collections;
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Expanded(
          child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("База Цен Аукциона", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E), elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.greenAccent), onPressed: _isLoading ? null : _fetchMarketData)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Поиск автомобиля по названию...",
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.greenAccent),
                filled: true, fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                : _errorMsg.isNotEmpty ? Center(child: Text(_errorMsg, style: const TextStyle(color: Colors.redAccent)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredCars.length,
                    itemBuilder: (ctx, i) {
                      final car = _filteredCars[i];
                      final name = car['name']?.toString() ?? "Неизвестно";
                      final price = car['price']?.toString() ?? "0";
                      final status = car['status']?.toString() ?? "Неизвестно";
                      
                      final formattedPrice = price == "0" ? "???" : price.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');

                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 6),
                                    _buildTrendIndicator(status),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text("$formattedPrice CR", style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. РАДАР С УМНОЙ ГРУППИРОВКОЙ И РУЧНЫМ ВВОДОМ
// ==========================================
class WatchlistTab extends StatefulWidget {
  final List<WatchlistItem> portfolio;
  final VoidCallback onUpdate;
  const WatchlistTab({super.key, required this.portfolio, required this.onUpdate});

  @override
  State<WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<WatchlistTab> {
  
  final List<String> _popularCars = [
    "2016 BENTLEY BENTAYGA", "ASTON MARTIN", "AUDI RS6", "BMW M3", "BMW M4", 
    "BUGATTI DIVO", "CHEVROLET CORVETTE", "FERRARI 599XX", "FERRARI F40", 
    "FORD MUSTANG", "HONDA CIVIC", "KOENIGSEGG JESKO", "LAMBORGHINI HURACAN", 
    "LAMBORGHINI SESTO", "MCLAREN F1", "MERCEDES-AMG", "NISSAN GT-R", 
    "PORSCHE 911 GT3", "PORSCHE TAYCAN", "TOYOTA SUPRA"
  ];

  List<String> _getSuggestions(String query) {
    Set<String> allCars = widget.portfolio.map((e) => e.name.toUpperCase()).toSet();
    allCars.addAll(_popularCars);
    if (query.isEmpty) return const [];
    return allCars.where((car) => car.contains(query.toUpperCase())).toList()..sort();
  }

  void _showManualAddDialog() {
    TextEditingController? autoNameController;
    final priceController = TextEditingController();
    final marketPriceController = TextEditingController(text: "20000000");
    final projectedController = TextEditingController(text: "20000000");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Добавить лот вручную", style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  return _getSuggestions(textEditingValue.text);
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  autoNameController = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Наименование лота", 
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: const Color(0xFF2C2C2C),
                      elevation: 8.0,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 250),
                        child: ListView.builder(
                          padding: EdgeInsets.zero, shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(option),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text(option, style: const TextStyle(color: Colors.white)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceController, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Цена закупки (CR)", labelStyle: TextStyle(color: Colors.white54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent))),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: marketPriceController, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Рынок СЕЙЧАС (CR)", labelStyle: TextStyle(color: Colors.white54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent))),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: projectedController, style: const TextStyle(color: Colors.amberAccent), keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Прогноз / Максимум (CR)", labelStyle: TextStyle(color: Colors.amberAccent), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent))),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              String name = autoNameController?.text.trim() ?? "";
              if (name.isEmpty) name = "Неизвестная машина";
              int price = int.tryParse(priceController.text) ?? 0;
              int market = int.tryParse(marketPriceController.text) ?? 20000000;
              int projected = int.tryParse(projectedController.text) ?? 20000000;
              
              final newItem = WatchlistItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name, buyPrice: price, targetPrice: market,
                projectedPrice: projected, status: "HOLD", 
                dateAdded: "${DateTime.now().day}.${DateTime.now().month}",
              );
              
              setState(() => widget.portfolio.insert(0, newItem));
              widget.onUpdate();
              Navigator.pop(ctx);
            },
            child: const Text("ДОБАВИТЬ", style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WatchlistItem item) {
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(text: item.buyPrice.toString());
    final marketPriceController = TextEditingController(text: item.targetPrice.toString());
    final projectedController = TextEditingController(text: item.projectedPrice.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Редактировать лот", style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Наименование", labelStyle: TextStyle(color: Colors.white54))),
              const SizedBox(height: 10),
              TextField(controller: priceController, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Цена закупки (CR)", labelStyle: TextStyle(color: Colors.white54))),
              const SizedBox(height: 10),
              TextField(controller: marketPriceController, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Рынок СЕЙЧАС (CR)", labelStyle: TextStyle(color: Colors.white54))),
              const SizedBox(height: 10),
              TextField(controller: projectedController, style: const TextStyle(color: Colors.amberAccent), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Прогноз / Максимум (CR)", labelStyle: TextStyle(color: Colors.amberAccent))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              setState(() {
                item.name = nameController.text.trim();
                item.buyPrice = int.tryParse(priceController.text) ?? item.buyPrice;
                item.targetPrice = int.tryParse(marketPriceController.text) ?? item.targetPrice;
                item.projectedPrice = int.tryParse(projectedController.text) ?? item.projectedPrice;
              });
              widget.onUpdate();
              Navigator.pop(ctx);
            },
            child: const Text("ОБНОВИТЬ", style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildIndividualCard(WatchlistItem item) {
    final currentNetProfit = (item.targetPrice * 0.85).round() - item.buyPrice;
    final projectedNetProfit = (item.projectedPrice * 0.85).round() - item.buyPrice;
    final roiPercent = (item.buyPrice > 0) ? ((projectedNetProfit / item.buyPrice) * 100).round() : 0;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent, child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        setState(() { widget.portfolio.remove(item); });
        widget.onUpdate();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Лот списан"), duration: Duration(seconds: 2)));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E), 
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12)
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Куплено: ${item.buyPrice} CR", style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text("Тек. профит: ", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text("${currentNetProfit > 0 ? '+' : ''}$currentNetProfit", style: TextStyle(color: currentNetProfit >= 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                  Row(
                    children: [
                      const Text("Прогноз: ", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text("🚀 +$projectedNetProfit", style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: Text("ROI ~ $roiPercent%", style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    setState(() { item.status = item.status == "HOLD" ? "READY" : "HOLD"; });
                    widget.onUpdate();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: item.status == "READY" ? Colors.green.shade800 : Colors.grey.shade800, borderRadius: BorderRadius.circular(6)),
                    child: Text(item.status == "READY" ? "🟢 ПРОДАТЬ" : "🟡 ОТЛЕЖКА", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  icon: const Icon(Icons.edit, color: Colors.white54, size: 22),
                  onPressed: () => _showEditDialog(context, item),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<WatchlistItem>> groupedPortfolio = {};
    for (var item in widget.portfolio) {
      String key = item.name.trim().toUpperCase();
      if (key.isEmpty) key = "НЕИЗВЕСТНАЯ МАШИНА";
      groupedPortfolio.putIfAbsent(key, () => []).add(item);
    }
    List<String> sortedKeys = groupedPortfolio.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text("Forza6Sniper | Радар активов"), backgroundColor: const Color(0xFF1E1E1E)),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: _showManualAddDialog,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: widget.portfolio.isEmpty
          ? const Center(child: Text("Склад пуст. Сканируйте аукцион для пополнения запасов.", style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 80),
              itemCount: sortedKeys.length,
              itemBuilder: (ctx, index) {
                String carName = sortedKeys[index];
                List<WatchlistItem> cars = groupedPortfolio[carName]!;

                int totalBuy = cars.fold(0, (sum, item) => sum + item.buyPrice);
                int avgBuyPrice = (totalBuy / cars.length).round();

                int totalProjectedNet = cars.fold(0, (sum, item) {
                  return sum + ((item.projectedPrice * 0.85).round() - item.buyPrice);
                });

                return Card(
                  color: const Color(0xFF161616),
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.greenAccent, width: 0.5)
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      iconColor: Colors.greenAccent,
                      collapsedIconColor: Colors.white54,
                      title: Text(
                        "$carName (Шт: ${cars.length})", 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text("Средняя цена закупки: $avgBuyPrice CR", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text("Потенциал группы: +$totalProjectedNet CR", style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      children: cars.map((item) => _buildIndividualCard(item)).toList(),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

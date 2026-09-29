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
      SnackBar(content: Text("✓ $carName сохранен!"), backgroundColor: Colors.green[800], duration: const Duration(seconds: 2)),
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

    if (mounted) {
      setState(() {
        _timeRemaining = "${diff.inDays}д ${diff.inHours % 24}ч ${diff.inMinutes % 60}м ${diff.inSeconds % 60}с до смены сезона";
      });
    }
  }

  Future<void> _fetchPlaylistData() async {
    setState(() { _isLoading = true; _errorMsg = ""; });
    try {
      final res = await http.get(Uri.parse(PLAYLIST_FEED_URL)).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _playlistData = jsonDecode(utf8.decode(res.bodyBytes));
          _isLoading = false;
        });
      } else {
        setState(() { _errorMsg = "Сервер недоступен (Код: ${res.statusCode})"; _isLoading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = "Ошибка сети: проверьте подключение"; _isLoading = false; });
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
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.greenAccent), onPressed: _isLoading ? null : _fetchPlaylistData)],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : _errorMsg.isNotEmpty ? Center(child: Text(_errorMsg, style: const TextStyle(color: Colors.redAccent)))
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text("СЕЗОН: ${_playlistData?['current_season']?.toString().toUpperCase() ?? 'WINTER'}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(_timeRemaining, style: const TextStyle(color: Colors.amberAccent, fontSize: 14)),
                const Divider(color: Colors.white24, height: 30),
                Text("Совет: ${_playlistData?['trading_advice'] ?? 'Отсутствует'}", style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
    );
  }
}

// ==========================================
// 2. СКАНЕР АУКЦИОНА С АВТОЧТЕНИЕМ НАЗВАНИЙ
// ==========================================
class ScannerTab extends StatefulWidget {
  final Function(String name, int price) onAddToPortfolio;
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
  
  int _detectedPrice = 0;
  String _detectedCarName = "";
  bool _isSnipeAlert = false;
  String _lastRawText = "Готов к сканированию...";
  String _statusBanner = "Наведите рамку на цены выкупа";

  @override
  void initState() {
    super.initState();
    _initCamera();
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

          final raw = recognizedText.text.trim();
          setState(() {
            _lastRawText = raw.isEmpty ? "Текст не найден" : (raw.length > 35 ? "${raw.substring(0, 35)}..." : raw.replaceAll('\n', ' '));
          });

          // 1. Поиск цены
          final priceRegex = RegExp(r'\b\d{1,3}(?:[., ]\d{3})*\b|\b\d+\b');
          final priceMatches = priceRegex.allMatches(raw);
          List<int> validPrices = [];
          
          for (final match in priceMatches) {
            String cleanNumStr = match.group(0)!.replaceAll(RegExp(r'[^0-9]'), '');
            if (cleanNumStr.isNotEmpty) {
              int parsedNum = int.parse(cleanNumStr);
              if (parsedNum >= 10000 && parsedNum <= 20000000) {
                validPrices.add(parsedNum);
              }
            }
          }

          // 2. Поиск названия машины (от 3 до 15 букв, игнорируя CR и MIN)
          final wordRegex = RegExp(r'\b[A-Za-zА-Яа-я]{3,15}\b');
          final wordMatches = wordRegex.allMatches(raw);
          List<String> validWords = [];
          
          for (final m in wordMatches) {
            String word = m.group(0)!;
            if (word.toUpperCase() != "MIN" && word.toUpperCase() != "МИН" && word.toUpperCase() != "CR") {
              validWords.add(word);
            }
          }

          String guessedName = validWords.take(3).join(" ");
          if (guessedName.isNotEmpty) {
             _detectedCarName = guessedName;
          }

          if (validPrices.isNotEmpty) {
            int minPrice = validPrices.reduce((curr, next) => curr < next ? curr : next);
            _processPrice(minPrice);
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

  void _showSaveDialog(int currentPrice, String guessedName) {
    final nameController = TextEditingController(text: guessedName);
    final priceController = TextEditingController(text: currentPrice.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Сохранить машину", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Название модели",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: priceController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Цена покупки (CR)",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              String name = nameController.text.trim();
              if (name.isEmpty) name = "Неизвестная машина";
              int price = int.tryParse(priceController.text) ?? currentPrice;
              
              widget.onAddToPortfolio(name, price);
              Navigator.pop(ctx);
            },
            child: const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          Positioned(
            top: 45, right: 20,
            child: FloatingActionButton.small(
              backgroundColor: _isTorchOn ? Colors.amberAccent : Colors.black54,
              onPressed: _toggleTorch,
              child: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: _isTorchOn ? Colors.black : Colors.white),
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
                  Text("OCR видит: $_lastRawText", style: const TextStyle(color: Colors.white60, fontSize: 11), overflow: TextOverflow.ellipsis),
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
// 3. РАДАР С РЕДАКТИРОВАНИЕМ И УДАЛЕНИЕМ (СВАЙПОМ)
// ==========================================
class WatchlistTab extends StatefulWidget {
  final List<WatchlistItem> portfolio;
  final VoidCallback onUpdate;
  const WatchlistTab({super.key, required this.portfolio, required this.onUpdate});

  @override
  State<WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<WatchlistTab> {
  
  void _showEditDialog(BuildContext context, int index) {
    final item = widget.portfolio[index];
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(text: item.buyPrice.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Редактировать лот", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Название", labelStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Цена покупки (CR)", labelStyle: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              setState(() {
                item.name = nameController.text.trim();
                item.buyPrice = int.tryParse(priceController.text) ?? item.buyPrice;
              });
              widget.onUpdate();
              Navigator.pop(ctx);
            },
            child: const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

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
                
                return Dismissible(
                  key: Key(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.redAccent,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (direction) {
                    setState(() { widget.portfolio.removeAt(i); });
                    widget.onUpdate();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Лот удален"), duration: Duration(seconds: 2)));
                  },
                  child: Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      title: Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text("Куплено: ${item.buyPrice} CR\nДобавлено: ${item.dateAdded}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("${netProfit >= 0 ? '+' : ''}$netProfit CR", style: TextStyle(color: netProfit >= 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () {
                                  setState(() { item.status = item.status == "HOLD" ? "READY" : "HOLD"; });
                                  widget.onUpdate();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: item.status == "READY" ? Colors.green.shade800 : Colors.grey.shade800, borderRadius: BorderRadius.circular(6)),
                                  child: Text(item.status == "READY" ? "🟢 ПРОДАТЬ" : "🟡 ОТЛЕЖКА", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                            onPressed: () => _showEditDialog(context, i),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Ошибка камер: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SelfLearningScannerApp(),
  ));
}

class SelfLearningScannerApp extends StatefulWidget {
  const SelfLearningScannerApp({super.key});

  @override
  State<SelfLearningScannerApp> createState() => _SelfLearningScannerAppState();
}

class _SelfLearningScannerAppState extends State<SelfLearningScannerApp> {
  CameraController? _controller;
  bool _isProcessing = false;

  // Имя отслеживаемого слота / пресета
  String _currentSlot = "Слот 1 (Авто)";
  final List<String> _slots = ["Слот 1 (Авто)", "Слот 2 (Авто)", "Слот 3 (Авто)"];

  // История цен для самообучения: Слот -> Список зафиксированных цен
  final Map<String, List<int>> _observedHistory = {};
  
  // Сохраненная рыночная медиана: Слот -> Цена
  final Map<String, int> _learnedMedians = {};

  int _detectedPrice = 0;
  int _lastProfit = 0;
  bool _isSnipeAlert = false;
  String _statusBanner = "Листайте лоты на экране для обучения модели";

  @override
  void initState() {
    super.initState();
    _loadStoredKnowledge();
    _initCamera();
  }

  // Загрузка ранее обученных данных из постоянной памяти
  Future<void> _loadStoredKnowledge() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("learned_medians");
    if (raw != null) {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      setState(() {
        decoded.forEach((key, val) {
          _learnedMedians[key] = val as int;
        });
      });
    }
  }

  // Сохранение обученной нормы
  Future<void> _persistKnowledge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("learned_medians", jsonEncode(_learnedMedians));
  }

  void _initCamera() {
    if (cameras.isNotEmpty) {
      _controller = CameraController(
        cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
      );
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

      // Офлайн-распознавание цифр через Tesseract (без сервисов Google)
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

  // Алгоритм самообучения и детекции снайпинга
  void _processIncomingPrice(int price) {
    if (!_observedHistory.containsKey(_currentSlot)) {
      _observedHistory[_currentSlot] = [];
    }

    final history = _observedHistory[_currentSlot]!;

    // Защита от дублей одного и того же кадра
    if (history.isEmpty || history.last != price) {
      history.add(price);
      if (history.length > 20) history.removeAt(0); // Скользящее окно из 20 лотов
    }

    // Расчет медианы при наличии минимум 5 наблюдений
    if (history.length >= 5) {
      final sorted = List<int>.from(history)..sort();
      final median = sorted[sorted.length ~/ 2];
      _learnedMedians[_currentSlot] = median;
      _persistKnowledge();
    }

    final int? currentMedian = _learnedMedians[_currentSlot];

    setState(() {
      _detectedPrice = price;

      if (currentMedian == null) {
        // Стадия накопления данных
        _isSnipeAlert = false;
        _statusBanner = " Обучение: собрано ${history.length}/5 лотов...";
      } else {
        // Стадия анализа: налог 15% в FH
        final netReturn = (currentMedian * 0.85).round();
        final profit = netReturn - price;
        final discount = ((currentMedian - price) / currentMedian * 100).round();
        _lastProfit = profit;

        if (discount >= 20 && profit > 150000) {
          _isSnipeAlert = true;
          _statusBanner = " СНАЙП! Скидка $discount% от нормы!";
          HapticFeedback.heavyImpact(); // Вибрация при удачном лоте
        } else if (profit > 0) {
          _isSnipeAlert = false;
          _statusBanner = "Норма (~${_formatCR(currentMedian)} CR). Профит мал: +${_formatCR(profit)} CR";
        } else {
          _isSnipeAlert = false;
          _statusBanner = "Обычная / высокая цена лота";
        }
      }
    });
  }

  void _resetCurrentModel() {
    setState(() {
      _observedHistory[_currentSlot]?.clear();
      _learnedMedians.remove(_currentSlot);
      _detectedPrice = 0;
      _isSnipeAlert = false;
      _statusBanner = "Память сброшена. Листайте лоты для переобучения.";
    });
    _persistKnowledge();
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
          // Камера
          Positioned.fill(child: CameraPreview(_controller!)),

          // Верхний блок: Выбор слота и статус обучения
          Positioned(
            top: 45,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      DropdownButton<String>(
                        value: _currentSlot,
                        dropdownColor: const Color(0xFF222222),
                        underline: const SizedBox(),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        items: _slots.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _currentSlot = val;
                              _detectedPrice = 0;
                              _isSnipeAlert = false;
                              _statusBanner = "Переключено на $val";
                            });
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        tooltip: "Сбросить память слота",
                        onPressed: _resetCurrentModel,
                      )
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        activeMedian != null
                            ? "Рыночная норма: ${_formatCR(activeMedian)} CR"
                            : "Статус: Накопление базы ($samplesCount/5)",
                        style: TextStyle(
                          color: activeMedian != null ? Colors.greenAccent : Colors.orangeAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        activeMedian != null ? "Обучено ✓" : "Калибровка",
                        style: TextStyle(
                          color: activeMedian != null ? Colors.greenAccent : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
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

          // Нижняя панель с аналитикой
          Positioned(
            bottom: 30,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isSnipeAlert
                    ? const Color(0xFF0D3D1E).withOpacity(0.95)
                    : Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isSnipeAlert ? Colors.greenAccent : Colors.white24,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusBanner,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isSnipeAlert ? Colors.greenAccent : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Лот в фокусе:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                            _detectedPrice > 0 ? "${_formatCR(_detectedPrice)} CR" : "—",
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("Чистый профит:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                            activeMedian != null && _detectedPrice > 0
                                ? "${_lastProfit > 0 ? '+' : ''}${_formatCR(_lastProfit)} CR"
                                : "—",
                            style: TextStyle(
                              color: _isSnipeAlert
                                  ? Colors.greenAccent
                                  : (_lastProfit > 0 ? Colors.white : Colors.redAccent),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

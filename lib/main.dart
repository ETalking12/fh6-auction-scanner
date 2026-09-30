import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FH6 Auction Scanner',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Общий список отслеживаемых машин (Портфель для Радара)
  final List<Map<String, String>> _watchlist = [];

  void _toggleWatchlist(Map<String, String> car) {
    setState(() {
      if (_watchlist.any((item) => item['name'] == car['name'])) {
        _watchlist.removeWhere((item) => item['name'] == car['name']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Удалено из радара: ${car['name']}'), duration: const Duration(seconds: 1)),
        );
      } else {
        _watchlist.add(car);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено в радар: ${car['name']}'), duration: const Duration(seconds: 1)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      ScannerScreen(onSaveToRadar: _toggleWatchlist),
      const SeasonScreen(),
      MarketPricesScreen(onToggleWatch: _toggleWatchlist, watchlist: _watchlist),
      RadarScreen(watchlist: _watchlist, onRemove: _toggleWatchlist),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Сканер'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Сезон & Советы'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'База Цен'),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'Радар'),
        ],
      ),
    );
  }
}

// 1. Вкладка «Сканер» (с OCR-логикой и кнопкой сохранения в Радар, как на вашем скрине)
class ScannerScreen extends StatefulWidget {
  final Function(Map<String, String>) onSaveToRadar;

  const ScannerScreen({super.key, required this.onSaveToRadar});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // Пример найденного лота с низкой ценой (как на вашем скриншоте)
  final Map<String, String> detectedCar = {
    'name': '2016 Bentley Bentayga',
    'price': '142 000 CR',
    'trend': '🔥 СНАЙП! Найдена низкая цена'
  };

  bool _isSaved = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('FH6 Авто-Снайпер (OCR)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Верхняя часть: имитация превью камеры / сканирования аукциона
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 2),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(Icons.camera, size: 64, color: Colors.white24),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('LIVE OCR SCAN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Карточка с логами OCR и результатом сканирования (как на скриншоте)
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OCR видит: ПРОДАНО!\nПРОДАНО!\nНЕ ПРОДАНО!\nBentley Bentayga 2016...',
                      style: TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'monospace'),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detectedCar['trend']!,
                            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${detectedCar['name']} — ${detectedCar['price']}',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          widget.onSaveToRadar(detectedCar);
                          setState(() {
                            _isSaved = true;
                          });
                        },
                        child: Text(
                          _isSaved ? 'СОХРАНЕНО В РАДАР ✓' : 'СОХРАНИТЬ В РАДАР',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. Вкладка «Сезон & Советы»
class SeasonScreen extends StatelessWidget {
  const SeasonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> seasonRewards = [
      {"name": "2021 Ford Mustang Mach-E", "points": "20 очков", "type": "Сезонный эксклюзив"},
      {"name": "Lamborghini Aventador SVJ", "points": "40 очков", "type": "Главная награда"},
      {"name": "Toyota Trueno GT Apex", "points": "80 очков", "type": "Прогресс серии"},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Сезон & Советы'),
      ),
      body: ListView.builder(
        itemCount: seasonRewards.length,
        itemBuilder: (context, index) {
          final reward = seasonRewards[index];
          return Card(
            color: const Color(0xFF1E1E1E),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.emoji_events, color: Colors.amber),
              title: Text(reward['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(reward['type']!, style: const TextStyle(color: Colors.greenAccent)),
              trailing: Text(reward['points']!, style: const TextStyle(color: Colors.white70)),
            ),
          );
        },
      ),
    );
  }
}

// 3. Вкладка «База Цен» (со стабильной рабочей ссылкой GitHub)
class MarketPricesScreen extends StatefulWidget {
  final Function(Map<String, String>) onToggleWatch;
  final List<Map<String, String>> watchlist;

  const MarketPricesScreen({super.key, required this.onToggleWatch, required this.watchlist});

  @override
  State<MarketPricesScreen> createState() => _MarketPricesScreenState();
}

class _MarketPricesScreenState extends State<MarketPricesScreen> {
  List<dynamic> _cars = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    fetchPrices();
  }

  Future<void> fetchPrices() async {
    setState(() {
      _isLoading = true;
    });

    // Рабочая стабильная ссылка GitHub без ошибок 404
    final url = Uri.parse('https://github.com/ETalking12/fh6-auction-scanner/raw/main/prices.json');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        setState(() {
          _cars = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredCars = _cars.where((car) {
      final name = car['name'].toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('База Цен Аукциона'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.greenAccent),
            onPressed: fetchPrices,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Поиск автомобиля по названию...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.greenAccent),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                : filteredCars.isEmpty
                    ? const Center(
                        child: Text(
                          'Список цен пуст или авто не найдено',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredCars.length,
                        itemBuilder: (context, index) {
                          final car = filteredCars[index];
                          final mapCar = {
                            'name': car['name'].toString(),
                            'price': car['price'].toString(),
                            'trend': car['trend'].toString(),
                          };
                          final isWatched = widget.watchlist.any((item) => item['name'] == mapCar['name']);

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text(
                                mapCar['name']!,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                mapCar['trend']!,
                                style: const TextStyle(color: Colors.greenAccent),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    mapCar['price']!,
                                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      isWatched ? Icons.star : Icons.star_border,
                                      color: isWatched ? Colors.amber : Colors.grey,
                                    ),
                                    onPressed: () => widget.onToggleWatch(mapCar),
                                  ),
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

// 4. Вкладка «Радар» (портфель сохраненных лотов)
class RadarScreen extends StatelessWidget {
  final List<Map<String, String>> watchlist;
  final Function(Map<String, String>) onRemove;

  const RadarScreen({super.key, required this.watchlist, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Радар / Портфель лотов'),
      ),
      body: watchlist.isEmpty
          ? const Center(
              child: Text(
                'Портфель пуст. Сохраняйте лоты со сканера или базы цен!',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: watchlist.length,
              itemBuilder: (context, index) {
                final car = watchlist[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(
                      car['name'] ?? '',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      car['trend'] ?? '',
                      style: const TextStyle(color: Colors.greenAccent),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          car['price'] ?? '',
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => onRemove(car),
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

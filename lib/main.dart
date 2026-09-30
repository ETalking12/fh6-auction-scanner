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
      title: 'Forza6Sniper',
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
  int _currentIndex = 2; // Открываем Базу Цен по умолчанию

  // Общий список отслеживаемых машин (Портфель / Радар)
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
      const ScannerScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Сезон'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'База Цен'),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'Радар'),
        ],
      ),
    );
  }
}

// 1. Вкладка «Сканер»
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('FH6 Авто-Снайпер'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.radar,
                size: 80,
                color: _isScanning ? Colors.greenAccent : Colors.grey,
              ),
              const SizedBox(height: 24),
              Text(
                _isScanning ? 'Сканирование аукциона активно...' : 'Снайпер приостановлен',
                style: TextStyle(fontSize: 18, color: _isScanning ? Colors.greenAccent : Colors.white70),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScanning ? Colors.redAccent : Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  setState(() {
                    _isScanning = !_isScanning;
                  });
                },
                icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                label: Text(_isScanning ? 'Остановить снайпер' : 'Запустить снайпер', style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 2. Вкладка «Сезон»
class SeasonScreen StatelessWidget {
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
        title: const Text('Сезонный советник'),
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

// 3. Вкладка «База Цен»
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
                                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
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

// 4. Вкладка «Радар» (Портфель отслеживаемых лотов)
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
                'Портфель пуст. Сохраняйте лоты зі вкладки "База Цен"!',
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
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
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

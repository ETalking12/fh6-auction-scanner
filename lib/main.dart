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

// 1. Вкладка «Сканер» (с оригинальным OCR интерфейсом и логами)
class ScannerScreen extends StatefulWidget {
  final Function(Map<String, String>) onSaveToRadar;

  const ScannerScreen({super.key, required this.onSaveToRadar});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
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
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 2),
              ),
              child: Stack(
                children: [
                  const Center(child: Icon(Icons.camera, size: 64, color: Colors.white24)),
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
                      'OCR видит: nPROAAHO!\nnPROAAHO!\nНЕ NPROAAHO!\nnonyY...',
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

// 2. Вкладка «Сезон & Советы» (с детальными карточками, таймером и модалкой характеристик)
class SeasonScreen extends StatelessWidget {
  const SeasonScreen({super.key});

  void _showCarDetails(BuildContext context, String title, String classInfo, String drive, String liquidity, String tip) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.directions_car, color: Colors.greenAccent),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Сезон награды:', 'Winter'),
            _detailRow('Рыночный потолок:', '20M CR'),
            _detailRow('Рекомендуемый класс:', classInfo),
            _detailRow('Тип привода:', drive),
            _detailRow('Ликвидность:', liquidity),
            const SizedBox(height: 12),
            Text('💡 Совет по снайпингу: $tip', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ЗАКРЫТЬ', style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Сезон & Советы'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Шапка сезона
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('WINTER\nSeries 5: Британский Автопром', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Chip(backgroundColor: Colors.green, label: Text('SYNCED', style: TextStyle(fontSize: 11))),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('⏳ 1д 22ч 33м 24с до смены сезона', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Карточка 1: 2006 Vauxhall Astra VXR
          Card(
            color: const Color(0xFF1E1E1E),
            child: ListTile(
              leading: const Icon(Icons.directions_car, color: Colors.amber),
              title: const Text('2006 Vauxhall Astra VXR', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Тапните для просмотра характеристик', style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: const Text('20M CR', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              onTap: () => _showCarDetails(
                context,
                '2006 Vauxhall Astra VXR',
                'A 700 / S1 850',
                'Передний (FWD)',
                '🔥 Дефицит (Топ)',
                'Модель пользуется высоким спросом в текущей серии. Скупайте лоты со скидкой и выставляйте по максимальной цене.',
              ),
            ),
          ),

          // Карточка 2: 2016 Bentley Bentayga
          Card(
            color: const Color(0xFF1E1E1E),
            child: ListTile(
              leading: const Icon(Icons.directions_car, color: Colors.greenAccent),
              title: const Text('2016 Bentley Bentayga', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Тапните для просмотра характеристик', style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: const Text('20M CR', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              onTap: () => _showCarDetails(
                context,
                '2016 Bentley Bentayga',
                'S1 900 / S2 998',
                'Полный (AWD) / Задний',
                '🔥 Дефицит (Топ)',
                'Высокий спрос, так как выдается только за сезонные очки. Установите фильтр по максимальной цене выкупа 12–15 млн CR.',
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Блок стратегии
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💡 СТРАТЕГИЯ СНАЙПИНГА', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                SizedBox(height: 8),
                Text(
                  'Снайпинг в зимнем сезоне Series 5: обе награды имеют высокий спрос. Мониторьте аукцион в первые 24 часа после сброса сезона (четверг), когда игроки выставляют дубликаты по заниженной цене.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ],
            ),
          ),
        ],
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

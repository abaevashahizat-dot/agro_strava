import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgroStravaApp());
}

class FieldLogEntry {
  final String fieldName;
  final String workType;
  final double distanceKm;
  final int pointsCount;
  final DateTime date;
  final String note;

  FieldLogEntry({
    required this.fieldName,
    required this.workType,
    required this.distanceKm,
    required this.pointsCount,
    required this.date,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'fieldName': fieldName,
        'workType': workType,
        'distanceKm': distanceKm,
        'pointsCount': pointsCount,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory FieldLogEntry.fromJson(Map<String, dynamic> json) => FieldLogEntry(
        fieldName: json['fieldName'],
        workType: json['workType'],
        distanceKm: (json['distanceKm'] as num).toDouble(),
        pointsCount: json['pointsCount'],
        date: DateTime.parse(json['date']),
        note: json['note'],
      );
}

class AgroStravaApp extends StatelessWidget {
  const AgroStravaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroStrava — Журнал агронома',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

// Проверка авторизации
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _currentUser;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUser = prefs.getString('current_user');
    });
  }

  void _onLoginSuccess(String username) {
    setState(() {
      _currentUser = username;
    });
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');
    setState(() {
      _currentUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }
    return FieldTrackerScreen(username: _currentUser!, onLogout: _logout);
  }
}

// ----------------- ЭКРАН ВХОДА И РЕГИСТРАЦИИ -----------------
class LoginScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните email и пароль')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_isRegistering) {
      // Регистрация нового агронома
      await prefs.setString('user_pass_$email', password);
      await prefs.setString('current_user', email);
      widget.onLoginSuccess(email);
    } else {
      // Вход
      final savedPass = prefs.getString('user_pass_$email');
      if (savedPass == password) {
        await prefs.setString('current_user', email);
        widget.onLoginSuccess(email);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный email или пароль')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50],
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.agriculture, size: 60, color: Colors.green),
                const SizedBox(height: 8),
                Text(
                  _isRegistering ? 'Регистрация агронома' : 'Вход в AgroStrava',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email / Логин',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: _submit,
                  child: Text(_isRegistering ? 'ЗАРЕГИСТРИРОВАТЬСЯ' : 'ВОЙТИ'),
                ),
                TextButton(
                  onPressed: () => setState(() => _isRegistering = !_isRegistering),
                  child: Text(_isRegistering
                      ? 'Уже есть аккаунт? Войти'
                      : 'Нет аккаунта? Зарегистрироваться'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------- ГЛАВНЫЙ ЭКРАН ТРЕКЕРА -----------------
class FieldTrackerScreen extends StatefulWidget {
  final String username;
  final VoidCallback onLogout;

  const FieldTrackerScreen({super.key, required this.username, required this.onLogout});

  @override
  State<FieldTrackerScreen> createState() => _FieldTrackerScreenState();
}

class _FieldTrackerScreenState extends State<FieldTrackerScreen> {
  bool _isTracking = false;
  List<LatLng> _routePoints = [];
  double _totalDistanceMeters = 0.0;

  List<FieldLogEntry> _journalLogs = [];

  StreamSubscription<Position>? _positionStreamSubscription;
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(54.8753, 69.1626);

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadUserLogs();
  }

  // Загрузка личных записей агронома из памяти
  Future<void> _loadUserLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString('logs_${widget.username}');
    if (rawJson != null) {
      final List<dynamic> list = jsonDecode(rawJson);
      setState(() {
        _journalLogs = list.map((e) => FieldLogEntry.fromJson(e)).toList();
      });
    }
  }

  // Сохранение записей текущего агронома
  Future<void> _saveUserLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = jsonEncode(_journalLogs.map((e) => e.toJson()).toList());
    await prefs.setString('logs_${widget.username}', rawJson);
  }

  Future<void> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
  }

  void _startTracking() {
    setState(() {
      _isTracking = true;
      _routePoints.clear();
      _totalDistanceMeters = 0.0;
    });

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      LatLng newPoint = LatLng(position.latitude, position.longitude);

      setState(() {
        if (_routePoints.isNotEmpty) {
          _totalDistanceMeters += Geolocator.distanceBetween(
            _routePoints.last.latitude,
            _routePoints.last.longitude,
            newPoint.latitude,
            newPoint.longitude,
          );
        }
        _routePoints.add(newPoint);
        _currentPosition = newPoint;
      });

      _mapController.move(newPoint, 16.0);
    });
  }

  void _stopTracking() {
    _positionStreamSubscription?.cancel();
    setState(() {
      _isTracking = false;
    });

    _showSaveLogDialog();
  }

  void _showSaveLogDialog() {
    String selectedField = 'Поле №1 (Ячмень)';
    String selectedWork = 'Осмотр / Обход';
    final noteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.assignment_turned_in, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Запись в журнал'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Пройдено: ${(_totalDistanceMeters / 1000).toStringAsFixed(2)} км (${_routePoints.length} точек GPS)'),
                    const SizedBox(height: 16),
                    const Text('Выберите поле:', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selectedField,
                      items: ['Поле №1 (Ячмень)', 'Поле №2 (Пшеница)', 'Поле №3 (Рапс)']
                          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                          .toList(),
                      onChanged: (val) => setDialogState(() => selectedField = val!),
                    ),
                    const SizedBox(height: 12),
                    const Text('Вид работы:', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selectedWork,
                      items: ['Осмотр / Обход', 'Закрытие влаги', 'Посев', 'Обработка СЗР', 'Уборка']
                          .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                          .toList(),
                      onChanged: (val) => setDialogState(() => selectedWork = val!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Заметка / Комментарий',
                        hintText: 'Например: обнаружены сорняки',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () async {
                    setState(() {
                      _journalLogs.add(
                        FieldLogEntry(
                          fieldName: selectedField,
                          workType: selectedWork,
                          distanceKm: _totalDistanceMeters / 1000,
                          pointsCount: _routePoints.length,
                          date: DateTime.now(),
                          note: noteController.text,
                        ),
                      );
                    });
                    await _saveUserLogs(); // Сохраняем в оффлайн-БД
                    Navigator.pop(context);
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AgroStrava (${widget.username})'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
            tooltip: 'Выйти из аккаунта',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition,
                    initialZoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.agro_strava',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          strokeWidth: 5.0,
                          color: Colors.blueAccent,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.navigation, color: Colors.red, size: 35),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Card(
                    color: Colors.white.withOpacity(0.9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Дистанция: ${(_totalDistanceMeters / 1000).toStringAsFixed(2)} км',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Мои записи: ${_journalLogs.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 15,
                  left: 30,
                  right: 30,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTracking ? Colors.red : Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    onPressed: _isTracking ? _stopTracking : _startTracking,
                    icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      _isTracking ? 'ЗАВЕРШИТЬ ОБХОД' : 'НАЧАТЬ ОБХОД ПОЛЯ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Журнал агронома: ${widget.username}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _journalLogs.isEmpty
                        ? const Center(
                            child: Text(
                              'У вас пока нет записей.\nПроведите обход поля и сохраните данные.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _journalLogs.length,
                            itemBuilder: (context, index) {
                              final log = _journalLogs.reversed.toList()[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  dense: true,
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.green,
                                    child: Icon(Icons.agriculture, color: Colors.white, size: 20),
                                  ),
                                  title: Text(
                                    '${log.fieldName} — ${log.workType}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Дистанция: ${log.distanceKm.toStringAsFixed(2)} км | Заметка: ${log.note.isNotEmpty ? log.note : "нет"}\n'
                                    'Время: ${log.date.hour}:${log.date.minute.toString().padLeft(2, '0')} (${log.date.day}.${log.date.month}.${log.date.year})',
                                  ),
                                ),
                              );
                            },
                          ),
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
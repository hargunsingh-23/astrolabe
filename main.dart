import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const AstrolabeApp());
}

// ==========================================
// 1. CORE LOGIC & FILTERS
// ==========================================
class LowPassFilter {
  final double alpha;
  double? _lastValue;

  LowPassFilter(this.alpha);

  double apply(double value) {
    if (_lastValue == null) {
      _lastValue = value;
      return value;
    }
    _lastValue = alpha * value + (1 - alpha) * _lastValue!;
    return _lastValue!;
  }
}

class RingBuffer {
  final int capacity;
  final List<double> data = [];

  RingBuffer(this.capacity);

  void add(double val) {
    if (data.length >= capacity) {
      data.removeAt(0);
    }
    data.add(val);
  }

  List<double> get snapshot => List.unmodifiable(data);
}

class LevelCalculator {
  static double calculateTilt(double x, double y, double z) {
    // Basic tilt angle calculation from accelerometer gravity vector
    double rad = atan2(sqrt(x * x + y * y), z);
    return rad * (180 / pi);
  }
}

// ==========================================
// 2. APP ROOT
// ==========================================
class AstrolabeApp extends StatelessWidget {
  const AstrolabeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Astrolabe',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0f172a),
        primaryColor: const Color(0xFF38bdf8),
      ),
      home: const HomeScreen(),
    );
  }
}

// ==========================================
// 3. HOME & SENSOR DASHBOARD
// ==========================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _accelX = 0.0, _accelY = 0.0, _accelZ = 0.0;
  final LowPassFilter _filterX = LowPassFilter(0.2);
  final RingBuffer _buffer = RingBuffer(50);
  StreamSubscription? _accelSub;

  @override
  void initState() {
    super.initState();
    _accelSub = accelerometerEventStream().listen((event) {
      setState(() {
        _accelX = _filterX.apply(event.x);
        _accelY = event.y;
        _accelZ = event.z;
        _buffer.add(_accelX);
      });
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double tilt = LevelCalculator.tiltAngle(_accelX, _accelY, _accelZ);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Astrolabe of the Vishanti 🧭'),
        backgroundColor: const Color(0xFF1e293b),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Hardware Sensors',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF38bdf8)),
            ),
            const SizedBox(height: 10),
            Card(
              color: const Color(0xFF1e293b),
              child: ListTile(
                leading: const Icon(Icons.speed, color: Colors.green),
                title: const Text('Accelerometer'),
                subtitle: Text('X: ${_accelX.toStringAsFixed(2)} | Y: ${_accelY.toStringAsFixed(2)} | Z: ${_accelZ.toStringAsFixed(2)}'),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Instrument Readings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF38bdf8)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF1e293b), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        const Text('Calculated Tilt'),
                        const SizedBox(height: 8),
                        Text('${tilt.toStringAsFixed(1)}°', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LevelCalculator {
  static double tiltAngle(double x, double y, double z) {
    return atan2(sqrt(x * x + y * y), z) * (180 / pi);
  }
}
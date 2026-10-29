import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const AstrolabeApp());
}

// ==========================================
// 1. CORE LOGIC, FILTERS & ANALYSERS
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
  static double tiltAngle(double x, double y, double z) {
    double rad = atan2(sqrt(x * x + y * y), z);
    return rad * (180 / pi);
  }
}

class StepDetector {
  double _lastMagnitude = 0.0;
  int _stepCount = 0;
  DateTime _lastStepTime = DateTime.now();

  int get stepCount => _stepCount;

  void reset() {
    _stepCount = 0;
  }

  void process(double x, double y, double z) {
    // Calculate magnitude of acceleration vector
    double magnitude = sqrt(x * x + y * y + z * z);
    double delta = (magnitude - _lastMagnitude).abs();

    // Peak threshold and debounce timer (300ms)
    if (delta > 1.3 && magnitude > 10.2) {
      final now = DateTime.now();
      if (now.difference(_lastStepTime).inMilliseconds > 300) {
        _stepCount++;
        _lastStepTime = now;
      }
    }
    _lastMagnitude = magnitude;
  }
}

class MotionAnalyser {
  static String getMotionState(List<double> buffer) {
    if (buffer.isEmpty) return 'Calibrating...';
    
    // Calculate variance of the buffer
    double mean = buffer.reduce((a, b) => a + b) / buffer.length;
    double variance = buffer.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / buffer.length;
    double stdDev = sqrt(variance);

    if (stdDev < 0.2) {
      return 'Stationary 🧘‍♂️';
    } else if (stdDev < 1.5) {
      return 'Walking 🚶‍♂️';
    } else {
      return 'Vigorous Motion ⚡';
    }
  }
}

class FrequencyAnalyser {
  static double estimateFrequency(List<double> buffer) {
    if (buffer.length < 10) return 0.0;

    double mean = buffer.reduce((a, b) => a + b) / buffer.length;
    int zeroCrossings = 0;

    for (int i = 0; i < buffer.length - 1; i++) {
      if ((buffer[i] - mean) * (buffer[i + 1] - mean) < 0) {
        zeroCrossings++;
      }
    }

    // Approximate sampling rate ~ 50Hz for accelerometer stream
    // Frequency = (zero crossings / 2) / duration in seconds
    double estimatedHz = (zeroCrossings / 2.0) * (50.0 / buffer.length);
    return estimatedHz.clamp(0.0, 10.0);
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
      debugShowCheckedModeBanner: false,
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
  final StepDetector _stepDetector = StepDetector();
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
        _stepDetector.process(_accelX, _accelY, _accelZ);
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
    String motionState = MotionAnalyser.getMotionState(_buffer.snapshot);
    double frequency = FrequencyAnalyser.estimateFrequency(_buffer.snapshot);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Astrolabe of the Vishanti 🧭'),
        backgroundColor: const Color(0xFF1e293b),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Steps',
            onPressed: () => setState(() => _stepDetector.reset()),
          )
        ],
      ),
      body: SingleChildScrollView(
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
              'Instrument Readings & Analysers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF38bdf8)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Calculated Tilt',
                    value: '${tilt.toStringAsFixed(1)}°',
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Step Counter',
                    value: '${_stepDetector.stepCount}',
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Motion State',
                    value: motionState,
                    color: Colors.orangeAccent,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Dominant Freq',
                    value: '${frequency.toStringAsFixed(1)} Hz',
                    color: Colors.purpleAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({required String title, required String value, required Color color, double fontSize = 24}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

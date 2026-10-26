import 'package:flutter_test/flutter_test.dart';
import 'package:astrolabe/main.dart';

void main() {
  test('LowPassFilter smoothing test', () {
    var filter = LowPassFilter(0.5);
    double val1 = filter.apply(10.0);
    expect(val1, 10.0);

    double val2 = filter.apply(20.0);
    expect(val2, 15.0); // 0.5 * 20 + 0.5 * 10
  });

  test('LevelCalculator tilt angle calculation', () {
    double angle = LevelCalculator.tiltAngle(0.0, 0.0, 9.8);
    expect(angle, closeTo(0.0, 0.1));
  });
}
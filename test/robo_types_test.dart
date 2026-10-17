import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/robo/robo.dart';

void main() {
  test('exactly three shapes', () {
    expect(RoboShape.values, <RoboShape>[
      RoboShape.square,
      RoboShape.circle,
      RoboShape.hexagon,
    ]);
  });

  test('exactly nine states with stable names', () {
    expect(RoboState.values.map((s) => s.name).toList(), <String>[
      'idle',
      'thinking',
      'searching',
      'listening',
      'speaking',
      'working',
      'happy',
      'error',
      'sleeping',
    ]);
  });
}

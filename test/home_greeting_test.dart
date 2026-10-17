import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/home/presentation/home_screen.dart';

void main() {
  group('Time-aware greeting', () {
    test('follows Night/Morning/Afternoon/Evening buckets', () {
      expect(homeGreeting(DateTime(2026, 5, 1, 0, 0), null), 'Good night 👋');
      expect(
        homeGreeting(DateTime(2026, 5, 1, 5, 59), 'Alex'),
        'Good night, Alex 👋',
      );
      expect(
        homeGreeting(DateTime(2026, 5, 1, 6, 0), 'Alex'),
        'Good morning, Alex 👋',
      );
      expect(
        homeGreeting(DateTime(2026, 5, 1, 11, 59), null),
        'Good morning 👋',
      );
      expect(
        homeGreeting(DateTime(2026, 5, 1, 12, 0), 'Alex'),
        'Good afternoon, Alex 👋',
      );
      expect(
        homeGreeting(DateTime(2026, 5, 1, 17, 59), null),
        'Good afternoon 👋',
      );
      expect(
        homeGreeting(DateTime(2026, 5, 1, 18, 0), 'Alex'),
        'Good evening, Alex 👋',
      );
      expect(
        homeGreeting(DateTime(2026, 5, 1, 21, 0), 'Alex'),
        'Good evening, Alex 👋',
      );
      expect(
        homeGreeting(DateTime(2026, 5, 1, 23, 59), null),
        'Good evening 👋',
      );
      expect(homeGreeting(DateTime(2026, 5, 1, 2, 0), null), 'Good night 👋');
    });
  });
}

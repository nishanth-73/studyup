import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the generated Android icon assets:
/// - launcher + foreground PNGs at every density with the exact adaptive
///   sizes, wired through mipmap-anydpi-v26 + manifest,
/// - status-bar PNGs at every density, transparent corners, white opaque
///   artwork covering most of the canvas (trimmed, prominent, unclipped).
///
/// Real image-codec work runs inside [WidgetTester.runAsync]: outside it,
/// the fake-async test zone never completes codec futures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> decode(String path) async {
    final bytes = await File(path).readAsBytes();
    return decodeImageFromList(bytes);
  }

  group('launcher icons', () {
    const foreground = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    const legacy = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };

    testWidgets('foreground + legacy PNGs exist at all densities', (
      tester,
    ) async {
      final sizes = await tester.runAsync(() async {
        final out = <String, List<int>>{};
        for (final entry in foreground.entries) {
          final img = await decode(
            'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_foreground.png',
          );
          out['fg:${entry.key}'] = [img.width, img.height];
        }
        for (final entry in legacy.entries) {
          final img = await decode(
            'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
          );
          out['raw:${entry.key}'] = [img.width, img.height];
        }
        return out;
      });
      for (final entry in foreground.entries) {
        expect(sizes!['fg:${entry.key}'], [entry.value, entry.value]);
      }
      for (final entry in legacy.entries) {
        expect(sizes!['raw:${entry.key}'], [entry.value, entry.value]);
      }
    });

    testWidgets('foreground holds the full wordmark, not a zoomed crop', (
      tester,
    ) async {
      // Regression guard: a stale foreground once shipped a zoomed
      // yellow-only crop with zero white letters.
      final counts = await tester.runAsync(() async {
        final img = await decode(
          'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
        );
        final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = raw!.buffer.asUint8List();
        var white = 0;
        var yellow = 0;
        for (var i = 0; i < bytes.length; i += 8) {
          if (bytes[i + 3] < 128) continue;
          if (bytes[i] > 200 && bytes[i + 1] > 200 && bytes[i + 2] > 200) {
            white++;
          } else if (bytes[i] > 200 &&
              bytes[i + 1] > 150 &&
              bytes[i + 2] < 170) {
            yellow++;
          }
        }
        return [white, yellow];
      });
      expect(counts![0], greaterThan(100), reason: 'white letters present');
      expect(counts[1], greaterThan(100), reason: 'yellow letters present');
    });

    test('adaptive XML + manifest wire the generated assets', () {
      final anydpi = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(anydpi, contains('@mipmap/ic_launcher_foreground'));
      expect(anydpi, contains('@color/ic_launcher_background'));
      // No dangling drawable reference may remain.
      expect(anydpi, isNot(contains('@drawable/ic_launcher_foreground')));
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    });
  });

  group('status-bar notification icon', () {
    const sizes = {
      'mdpi': 24,
      'hdpi': 36,
      'xhdpi': 48,
      'xxhdpi': 72,
      'xxxhdpi': 96,
    };

    testWidgets('PNGs sized per density, trimmed, white, opaque core', (
      tester,
    ) async {
      final report = await tester.runAsync(() async {
        final out = <String, Map<String, int>>{};
        for (final entry in sizes.entries) {
          final img = await decode(
            'android/app/src/main/res/drawable-${entry.key}/ic_stat_studyup.png',
          );
          final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          final bytes = raw!.buffer.asUint8List();
          int alphaAt(int x, int y) => bytes[(y * img.width + x) * 4 + 3];
          var minX = img.width, minY = img.height, maxX = -1, maxY = -1;
          var whiteCore = 0;
          for (var y = 0; y < img.height; y++) {
            for (var x = 0; x < img.width; x++) {
              final o = (y * img.width + x) * 4;
              if (bytes[o + 3] > 12) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
                if (bytes[o] > 200 &&
                    bytes[o + 1] > 200 &&
                    bytes[o + 2] > 200) {
                  whiteCore++;
                }
              }
            }
          }
          out[entry.key] = {
            'w': img.width,
            'h': img.height,
            'corner': alphaAt(0, 0),
            'bboxW': maxX - minX + 1,
            'bboxH': maxY - minY + 1,
            'white': whiteCore,
          };
        }
        return out;
      });
      for (final entry in sizes.entries) {
        final r = report![entry.key]!;
        expect(r['w'], entry.value, reason: entry.key);
        expect(r['h'], entry.value, reason: entry.key);
        expect(r['corner'], 0, reason: '${entry.key} transparent corner');
        expect(r['bboxW'], greaterThanOrEqualTo(entry.value * 0.6));
        expect(r['bboxH'], greaterThanOrEqualTo(entry.value * 0.6));
        expect(r['white'], greaterThan(0));
      }
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/svg_art/data/smil.dart';
import 'package:studyup/features/svg_art/presentation/svg_art.dart'
    show SvgArt, SvgArtController, ensureSmilImages;

/// Paints each illustration across its full loop (plus wrap-around) so
/// every gate, morph, dash, motion, clip and transform track executes
/// at least once. Any throw (unknown command, bad track, clip miss)
/// fails the test.
///
/// Scenes are parsed up front (asset loads are flaky under fake async);
/// the widget still runs its full play/rest/ticker path.
Future<void> _pumpLoop(
  WidgetTester tester,
  String asset, {
  required double loopSeconds,
}) async {
  final source = await tester.runAsync(() => rootBundle.loadString(asset));
  final scene = SmilScene.parse(source!);
  // Raster decode needs real async; the widget skips already-decoded art.
  await tester.runAsync(() => ensureSmilImages(scene));
  final controller = SvgArtController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SvgArt(
          asset: asset,
          scene: scene,
          controller: controller,
          width: 200,
          height: 200,
        ),
      ),
    ),
  );
  await tester.pump();
  // Image-heavy scenes finish async raster decode after a few frames.
  for (var i = 0; i < 30 && !controller.isPlaying; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(tester.takeException(), isNull);
  expect(controller.isPlaying, isTrue);

  // Step through the whole loop in ~10 slices, then past the wrap point.
  final stepMs = (loopSeconds * 1000 / 10).round();
  for (var i = 0; i < 12; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
    expect(
      tester.takeException(),
      isNull,
      reason: '$asset frame $i threw while painting',
    );
  }

  controller.showRest();
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(controller.isPlaying, isFalse);

  controller.play();
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
  expect(controller.isPlaying, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cases = [
    ('assets/images/today_session.svg', 2.4),
    ('assets/images/session.svg', 2.4),
    ('assets/images/tasks.svg', 3.9),
    ('assets/images/onboarding_1.svg', 6.0),
    ('assets/images/onboarding_2.svg', 6.0),
    ('assets/images/onboarding_3.svg', 6.0),
    ('assets/images/login_character.svg', 2.0),
    ('assets/images/team_goals.svg', 3.0),
  ];
  for (final (asset, loop) in cases) {
    testWidgets('$asset paints across its ${loop}s loop', (tester) async {
      await _pumpLoop(tester, asset, loopSeconds: loop);
    });
  }
}

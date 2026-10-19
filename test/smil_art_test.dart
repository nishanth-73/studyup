import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/svg_art/data/smil.dart';
import 'package:studyup/features/svg_art/presentation/svg_art.dart'
    show ensureSmilImages;

Future<SmilScene> _load(String asset) async {
  final source = await rootBundle.loadString(asset);
  return SmilScene.parse(source);
}

void _walkCounts(SmilNode node, Map<String, int> counts) {
  switch (node) {
    case SmilGroup(
      :final children,
      :final gate,
      :final motion,
      :final opacityTrack,
      :final dashTrack,
      :final dashOffsetTrack,
    ):
      counts['groups'] = (counts['groups'] ?? 0) + 1;
      if (gate != null) counts['gates'] = (counts['gates'] ?? 0) + 1;
      if (motion != null) counts['motion'] = (counts['motion'] ?? 0) + 1;
      if (opacityTrack != null) {
        counts['opacity'] = (counts['opacity'] ?? 0) + 1;
      }
      if (dashTrack != null || dashOffsetTrack != null) {
        counts['dash'] = (counts['dash'] ?? 0) + 1;
      }
      for (final child in children) {
        _walkCounts(child, counts);
      }
    case SmilLeaf(
      :final morph,
      :final setFrames,
      :final gate,
      :final paint,
      :final motion,
    ):
      counts['leaves'] = (counts['leaves'] ?? 0) + 1;
      if (morph != null) counts['morphs'] = (counts['morphs'] ?? 0) + 1;
      if (setFrames != null) {
        counts['sets'] = (counts['sets'] ?? 0) + 1;
      }
      if (gate != null) counts['gates'] = (counts['gates'] ?? 0) + 1;
      if (paint.dashTrack != null || paint.dashOffsetTrack != null) {
        counts['dash'] = (counts['dash'] ?? 0) + 1;
      }
      if (motion != null) counts['motion'] = (counts['motion'] ?? 0) + 1;
    case SmilImage():
      counts['images'] = (counts['images'] ?? 0) + 1;
  }
}

void _walkAll(SmilScene scene, Map<String, int> counts) {
  for (final root in scene.roots) {
    _walkCounts(root, counts);
  }
  for (final mask in scene.masks.values) {
    for (final child in mask.children) {
      _walkCounts(child, counts);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SMIL scene parsing', () {
    test('today_session.svg: loop with animated clip paths', () async {
      final scene = await _load('assets/images/today_session.svg');
      expect(scene.width, 120);
      expect(scene.height, 120);
      expect(scene.loopSeconds, closeTo(2.0, 0.001));
      final animatedClips = scene.clips.values
          .where((clip) => clip.morph != null)
          .toList();
      expect(animatedClips, hasLength(2));
      for (final clip in animatedClips) {
        expect(
          clip.geometryAt(0, scene.loopSeconds).numbers,
          isNot(equals(clip.geometryAt(1, scene.loopSeconds).numbers)),
        );
      }
      final counts = <String, int>{};
      for (final root in scene.roots) {
        _walkCounts(root, counts);
      }
      expect(counts['gates'], 8);
      expect(counts['leaves'], greaterThan(0));
    });

    test('session.svg: 2.4s loop with dash + opacity + clip', () async {
      final scene = await _load('assets/images/session.svg');
      expect(scene.width, 250);
      expect(scene.height, 250);
      expect(scene.loopSeconds, closeTo(2.4, 0.001));
      expect(scene.clips.length, 1);
      final counts = <String, int>{};
      for (final root in scene.roots) {
        _walkCounts(root, counts);
      }
      expect(counts['gates'], 24);
      expect(counts['morphs'], 8);
      expect(counts['dash'], greaterThan(0));
      expect(counts['motion'], isNull);
    });

    test('tasks.svg: 3.9s loop with motion + dash', () async {
      final scene = await _load('assets/images/tasks.svg');
      expect(scene.width, 800);
      expect(scene.height, 800);
      expect(scene.loopSeconds, closeTo(3.9, 0.001));
      final counts = <String, int>{};
      for (final root in scene.roots) {
        _walkCounts(root, counts);
      }
      expect(counts['gates'], 25);
      expect(counts['motion'], 2);
      expect(counts['dash'], greaterThan(0));
    });

    test('onboarding_1.svg: 6s loop, no masks/filters/images', () async {
      final scene = await _load('assets/images/onboarding_1.svg');
      expect(scene.width, 1200);
      expect(scene.height, 1200);
      expect(scene.loopSeconds, closeTo(6.0, 0.001));
      expect(scene.masks, isEmpty);
      expect(scene.whitenFilters, isEmpty);
      final counts = <String, int>{};
      _walkAll(scene, counts);
      expect(counts['leaves'], greaterThan(0));
      expect(counts['images'], isNull);
    });

    test('onboarding_2.svg: 6s loop with masks + whiten filters', () async {
      final scene = await _load('assets/images/onboarding_2.svg');
      expect(scene.width, 1200);
      expect(scene.height, 1200);
      expect(scene.loopSeconds, closeTo(6.0, 0.001));
      expect(scene.masks.length, 3);
      expect(scene.whitenFilters.length, 2);
      final counts = <String, int>{};
      _walkAll(scene, counts);
      expect(counts['leaves'], greaterThan(0));
    });

    test('onboarding_3.svg: 6s loop with mask + whiten filter', () async {
      final scene = await _load('assets/images/onboarding_3.svg');
      expect(scene.width, 1200);
      expect(scene.height, 1200);
      expect(scene.loopSeconds, closeTo(6.0, 0.001));
      expect(scene.masks.length, 1);
      expect(scene.whitenFilters.length, 1);
      final counts = <String, int>{};
      _walkAll(scene, counts);
      expect(counts['leaves'], greaterThan(0));
    });

    test('login_character.svg: 2s loop with stepped d sets', () async {
      final scene = await _load('assets/images/login_character.svg');
      expect(scene.width, 1080);
      expect(scene.height, 1080);
      expect(scene.loopSeconds, closeTo(2.0, 0.001));
      final counts = <String, int>{};
      _walkAll(scene, counts);
      expect(counts['sets'], greaterThan(0));
      expect(counts['leaves'], greaterThan(0));
    });

    test('team_goals.svg: 3s loop with embedded images', () async {
      final scene = await _load('assets/images/team_goals.svg');
      expect(scene.width, 1080);
      expect(scene.height, 1080);
      expect(scene.loopSeconds, closeTo(3.0, 0.001));
      final counts = <String, int>{};
      _walkAll(scene, counts);
      expect(counts['images'], 3);
      // Embedded rasters must decode or the screen stays empty.
      await ensureSmilImages(scene);
      final images = <SmilImage>[];
      void collect(SmilNode node) {
        switch (node) {
          case SmilGroup(:final children):
            for (final child in children) {
              collect(child);
            }
          case SmilImage():
            images.add(node);
          case SmilLeaf():
            break;
        }
      }

      for (final root in scene.roots) {
        collect(root);
      }
      expect(images.length, 3);
      for (final image in images) {
        expect(image.image, isNotNull);
        expect(image.width, greaterThan(0));
        expect(image.height, greaterThan(0));
      }
    });
  });
}

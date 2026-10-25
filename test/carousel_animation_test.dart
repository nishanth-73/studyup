import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/svg_art/data/smil.dart';

/// The first Home carousel slide (session.svg) must genuinely animate.
///
/// Raster screenshots deadlock under flutter_tester, so this proves
/// animation at the timeline level instead: sampling every track in the
/// parsed scene at two loop times must yield different values. Combined
/// with the pump test (the widget plays the loop without errors), this
/// verifies the slide's artwork advances instead of sitting frozen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<double> sampleAllTracks(SmilScene scene, double tSeconds) {
    final out = <double>[];
    void trackNumeric(NumericTrack t) =>
        out.addAll(t.sample(tSeconds, scene.loopSeconds));
    void walk(SmilNode node) {
      switch (node) {
        case SmilGroup(
          :final transformTracks,
          :final gate,
          :final opacityTrack,
          :final motion,
          :final dashTrack,
          :final dashOffsetTrack,
          :final children,
        ):
          for (final entry in transformTracks) {
            trackNumeric(entry.track);
          }
          if (gate != null) {
            out.add(gate.visibleAt(tSeconds, scene.loopSeconds) ? 1 : 0);
          }
          if (opacityTrack != null) trackNumeric(opacityTrack);
          if (motion != null) {
            out.addAll(motion.sample(tSeconds, scene.loopSeconds));
          }
          if (dashTrack != null) trackNumeric(dashTrack);
          if (dashOffsetTrack != null) trackNumeric(dashOffsetTrack);
          for (final child in children) {
            walk(child);
          }
        case SmilLeaf(
          :final morph,
          :final transformTracks,
          :final gate,
          :final opacityTrack,
          :final motion,
          :final paint,
        ):
          for (final entry in transformTracks) {
            trackNumeric(entry.track);
          }
          if (morph != null) trackNumeric(morph);
          if (gate != null) {
            out.add(gate.visibleAt(tSeconds, scene.loopSeconds) ? 1 : 0);
          }
          if (opacityTrack != null) trackNumeric(opacityTrack);
          if (motion != null) {
            out.addAll(motion.sample(tSeconds, scene.loopSeconds));
          }
          if (paint.dashTrack != null) trackNumeric(paint.dashTrack!);
          if (paint.dashOffsetTrack != null) {
            trackNumeric(paint.dashOffsetTrack!);
          }
        case SmilImage():
          break;
      }
    }

    for (final root in scene.roots) {
      walk(root);
    }
    return out;
  }

  test('session.svg advances values over its loop', () async {
    final source = await rootBundle.loadString('assets/images/session.svg');
    final scene = SmilScene.parse(source);
    expect(scene.loopSeconds, greaterThan(0));
    final a = sampleAllTracks(scene, 0.2);
    final b = sampleAllTracks(scene, 1.4);
    expect(a.length, greaterThan(0));
    expect(a.length, b.length);
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-9) diff++;
    }
    // A 2.4s SMIL loop must move a visible number of tracks in 1.2s.
    expect(diff, greaterThan(10));
  });
}

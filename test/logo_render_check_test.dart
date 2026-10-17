import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  testWidgets('logo render keeps white letters', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final svg = File(r'C:\Users\medur\Downloads\logo.svg').readAsStringSync();
    final key = UniqueKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox.square(
              dimension: 400,
              child: SvgPicture.string(svg, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final boundary =
        tester.element(find.byKey(key)).renderObject! as RenderRepaintBoundary;
    final img = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0));
    final raw = await tester.runAsync(
      () => img!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = raw!.buffer.asUint8List();
    var white = 0;
    var yellow = 0;
    for (var i = 0; i < bytes.length; i += 16) {
      final a = bytes[i + 3];
      if (a < 128) continue;
      if (bytes[i] > 200 && bytes[i + 1] > 200 && bytes[i + 2] > 200) {
        white++;
      } else if (bytes[i] > 200 && bytes[i + 1] > 150 && bytes[i + 2] < 170) {
        yellow++;
      }
    }
    // ignore: avoid_print
    print('white=$white yellow=$yellow');
    expect(white, greaterThan(100));
    expect(yellow, greaterThan(100));
  });
}

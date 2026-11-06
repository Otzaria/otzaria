import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/macos_font_probe.dart';

void main() {
  initializeMacosFontProbeBinding();

  testWidgets(
    'an async native-style callback paints without an explicit pump',
    (
      tester,
    ) async {
      final painted = Completer<void>();
      late StateSetter update;
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return CustomPaint(painter: _Frame(changed, painted));
            },
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      update(() => changed = true);
      await painted.future.timeout(const Duration(seconds: 2));
      expect(changed, isTrue);
    },
  );
}

class _Frame extends CustomPainter {
  _Frame(this.changed, this.painted);
  final bool changed;
  final Completer<void> painted;

  @override
  void paint(Canvas canvas, Size size) {
    if (changed && !painted.isCompleted) painted.complete();
  }

  @override
  bool shouldRepaint(_Frame oldDelegate) => oldDelegate.changed != changed;
}

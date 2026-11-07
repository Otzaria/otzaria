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

  testWidgets('a native timeout permits live scene disposal and later pumps', (
    tester,
  ) async {
    final scene = ValueNotifier<Widget>(const SizedBox.shrink());
    final mounted = Completer<void>();
    final progress = FontProbeViewProgress(0);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<Widget>(
          valueListenable: scene,
          builder: (context, child, _) => child,
        ),
      ),
    );
    scene.value = _LifecycleFrame(progress, mounted);
    await mounted.future.timeout(const Duration(seconds: 2));
    final nativeResult = Completer<void>();
    await expectLater(
      nativeResult.future.timeout(const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    TestAsyncUtils.guardSync();
    scene.value = const SizedBox.shrink();
    await progress.whenDisposed.timeout(const Duration(seconds: 2));
    expect(progress.report['disposed'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    scene.dispose();
    nativeResult.complete();
  });
}

class _LifecycleFrame extends StatefulWidget {
  const _LifecycleFrame(this.progress, this.mounted);
  final FontProbeViewProgress progress;
  final Completer<void> mounted;
  @override
  State<_LifecycleFrame> createState() => _LifecycleFrameState();
}

class _LifecycleFrameState extends State<_LifecycleFrame> {
  @override
  void initState() {
    super.initState();
    widget.progress.mounted();
    widget.mounted.complete();
  }

  @override
  void dispose() {
    widget.progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
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

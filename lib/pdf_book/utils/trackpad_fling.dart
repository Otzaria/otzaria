import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// המשך התנועה אחרי הרמת האצבעות מגלילת pan בלוח מגע (issue #3491), כמו
/// בקורא הטקסט. נעצר בכל מגע, מחווה או גלילה חדשים.
class TrackpadFling {
  TrackpadFling({required this.onDelta, required this.onInterrupt});

  /// תזוזה בכיוון האצבעות, כמו [TrackpadPanRecognizer.onPanDelta].
  final void Function(Offset delta) onDelta;

  /// מגע או מחווה חדשים עצרו את ההחלקה.
  final VoidCallback onInterrupt;

  Ticker? _ticker;

  /// מתחיל החלקה במהירות [velocity] (פיקסלים לשנייה, בכיוון האצבעות).
  void start(TickerProvider vsync, Offset velocity) {
    stop();
    if (velocity.distance < kMinFlingVelocity) return;
    final x = ClampingScrollSimulation(position: 0, velocity: velocity.dx);
    final y = ClampingScrollSimulation(position: 0, velocity: velocity.dy);
    var last = Offset.zero;
    _ticker = vsync.createTicker((elapsed) {
      final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      final now = Offset(x.x(t), y.x(t));
      if (now != last) onDelta(now - last);
      last = now;
      if (x.isDone(t) && y.isDone(t)) stop();
    })..start();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerScrollEvent || event is PointerScaleEvent) {
      stop();
    } else if (event is PointerDownEvent || event is PointerPanZoomStartEvent) {
      stop();
      onInterrupt();
    }
  }

  void stop() {
    final ticker = _ticker;
    if (ticker == null) return;
    _ticker = null;
    ticker.dispose();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }
}

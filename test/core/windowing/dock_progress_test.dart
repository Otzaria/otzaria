import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/dock_progress.dart';
import 'package:window_manager/legacy.dart';

void main() {
  late _RecordingGeometry geometry;

  setUp(() {
    geometry = _RecordingGeometry();
    DockProgress.setGeometryForTesting(geometry);
    DockProgress.debugIsSupportedOverride = true;
  });

  tearDown(DockProgress.resetForTesting);

  test('התקדמות מדידה נשלחת כערך שבין 0 ל-1', () async {
    await DockProgress.show(value: 0.25);
    expect(geometry.sent, [0.25]);
  });

  test('ערך ללא התקדמות מדידה נשלח כחיווי בלתי-מוגדר', () async {
    await DockProgress.show();
    expect(geometry.sent.single, greaterThan(1));
  });

  test('הסתרה נשלחת כערך שלילי', () async {
    await DockProgress.hide();
    expect(geometry.sent.single, lessThan(0));
  });

  test('ערך מחוץ לתחום נחתך', () async {
    await DockProgress.show(value: 1.8);
    await DockProgress.show(value: -0.5);
    expect(geometry.sent, [1.0, 0.0]);
  });

  test('שינוי דק מאחוז אינו מייצר קריאת ערוץ נוספת', () async {
    await DockProgress.show(value: 0.5);
    await DockProgress.show(value: 0.5001);
    await DockProgress.show(value: 0.51);
    expect(geometry.sent, [0.5, 0.51]);
  });

  test('מחוץ למק לא נשלח דבר', () async {
    DockProgress.debugIsSupportedOverride = false;
    await DockProgress.show(value: 0.5);
    await DockProgress.hide();
    expect(geometry.sent, isEmpty);
  });

  test('כשל בערוץ אינו מתפשט', () async {
    DockProgress.setGeometryForTesting(_ThrowingGeometry());
    DockProgress.debugIsSupportedOverride = true;
    await expectLater(DockProgress.show(value: 0.5), completes);
  });
}

class _RecordingGeometry implements AppWindowGeometry {
  final List<double> sent = [];

  @override
  Future<void> setProgressBar(double progress) async => sent.add(progress);

  @override
  Future<Rect> getBounds() async => Rect.zero;
  @override
  Future<void> setBounds(Rect bounds) async {}
  @override
  Future<void> setSize(Size size) async {}
  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}
}

class _ThrowingGeometry extends _RecordingGeometry {
  @override
  Future<void> setProgressBar(double progress) async =>
      throw StateError('channel down');
}

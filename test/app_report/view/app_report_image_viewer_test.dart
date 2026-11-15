import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/view/widgets/app_report_image_viewer.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import '../../support/golden_fonts.dart';

Future<AppReportImage> _image(
  WidgetTester tester, {
  String name = 'shot.png',
}) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 60);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return AppReportImage(
      bytes: data!.buffer.asUint8List(),
      fileName: name,
      mimeType: 'image/png',
    );
  }))!;
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(done(), isTrue);
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });
  Future<void> open(
    WidgetTester tester,
    AppReportImage image, {
    ValueChanged<AppReportImage>? saved,
    Size size = const Size(1200, 900),
    double scale = 1,
    bool editable = true,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialogUntilTornDown<AppReportImage>(
                  context: context,
                  builder: (_) => AppReportImageViewer(
                    image: image,
                    accept: editable ? (_) => true : null,
                  ),
                );
                if (result != null) saved?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await _wait(
      tester,
      () => find
          .byKey(const ValueKey('app-report-image-canvas'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dirty close asks, cancel retains marks, discard closes', (
    tester,
  ) async {
    await open(tester, await _image(tester));
    await tester.tap(find.byKey(const ValueKey('app-report-image-mark')));
    await tester.pump();
    final area = tester.getRect(
      find.byKey(const ValueKey('app-report-image-canvas')),
    );
    await tester.dragFrom(
      area.topLeft + area.size.center(Offset.zero) * .4,
      area.size.center(Offset.zero) * .5,
    );
    await tester.pump();
    await tester.tap(find.text('סגור').last);
    await tester.pumpAndSettle();
    expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
    await tester.tap(find.text('המשך לערוך'));
    await tester.pumpAndSettle();
    expect(find.byType(AppReportImageViewer), findsOneWidget);
    await tester.tap(find.text('סגור').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('סגור בלי לשמור'));
    await tester.pumpAndSettle();
    expect(find.byType(AppReportImageViewer), findsNothing);
  });

  testWidgets('compact portrait at text1.3 fits', (tester) async {
    await open(
      tester,
      await _image(tester),
      size: const Size(360, 800),
      scale: 1.3,
    );
    expect(tester.takeException(), isNull);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'כיבוי סימון מבטל גרירה ומאפשר סימון מחדש (${cancel ? 'cancel' : 'up'})',
      (tester) async {
        await open(tester, await _image(tester));
        final toggle = find.byKey(const ValueKey('app-report-image-mark'));
        final save = find.byKey(const ValueKey('app-report-image-save-marks'));
        await tester.tap(toggle);
        await tester.pump();
        final area = tester.getRect(
          find.byKey(const ValueKey('app-report-image-canvas')),
        );
        final first = await tester.startGesture(area.center, pointer: 40);
        await first.moveBy(const Offset(30, 30));
        await tester.pump();
        await tester.tap(toggle, pointer: 41);
        await tester.pump();
        if (cancel) {
          await first.cancel();
        } else {
          await first.up();
        }
        await tester.pump();
        expect(tester.widget<ActionButton>(save).onPressed, isNull);
        await tester.tap(toggle, pointer: 42);
        await tester.pump();
        await tester.dragFrom(
          area.topLeft + const Offset(80, 80),
          const Offset(100, 100),
        );
        await tester.pump();
        expect(tester.widget<ActionButton>(save).onPressed, isNotNull);
      },
    );
  }

  testWidgets('כיבוי באמצע גרירה שומר סימונים קודמים ואת הגנת הסגירה', (
    tester,
  ) async {
    await open(tester, await _image(tester));
    final toggle = find.byKey(const ValueKey('app-report-image-mark'));
    final save = find.byKey(const ValueKey('app-report-image-save-marks'));
    final undo = find.byKey(const ValueKey('app-report-image-undo'));
    await tester.tap(toggle);
    await tester.pump();
    final area = tester.getRect(
      find.byKey(const ValueKey('app-report-image-canvas')),
    );
    await tester.dragFrom(
      area.topLeft + const Offset(80, 80),
      const Offset(100, 100),
    );
    await tester.pump();
    final finger = await tester.startGesture(area.center, pointer: 40);
    await finger.moveBy(const Offset(30, 30));
    await tester.pump();
    await tester.tap(toggle, pointer: 41);
    await tester.pump();
    await finger.up();
    await tester.pump();
    expect(tester.widget<ActionButton>(save).onPressed, isNotNull);
    expect(tester.widget<AppIconButton>(undo).onPressed, isNotNull);
    await tester.tap(find.text('סגור').last);
    await tester.pumpAndSettle();
    expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
    await tester.tap(find.text('המשך לערוך'));
    await tester.pumpAndSettle();
    await tester.tap(undo);
    await tester.pump();
    expect(tester.widget<ActionButton>(save).onPressed, isNull);
    await tester.tap(find.text('סגור').last);
    await tester.pumpAndSettle();
    expect(find.byType(AppReportImageViewer), findsNothing);
  });

  testWidgets('ביטול pointer מבטל רק את הטיוטה ומאפשר גרירה חדשה', (
    tester,
  ) async {
    await open(tester, await _image(tester));
    final save = find.byKey(const ValueKey('app-report-image-save-marks'));
    await tester.tap(find.byKey(const ValueKey('app-report-image-mark')));
    await tester.pump();
    final area = tester.getRect(
      find.byKey(const ValueKey('app-report-image-canvas')),
    );
    final finger = await tester.startGesture(area.center);
    await finger.moveBy(const Offset(30, 30));
    await tester.pump();
    await finger.cancel();
    await tester.pump();
    expect(tester.widget<ActionButton>(save).onPressed, isNull);
    await tester.dragFrom(
      area.topLeft + const Offset(80, 80),
      const Offset(100, 100),
    );
    await tester.pump();
    expect(tester.widget<ActionButton>(save).onPressed, isNotNull);
  });

  testWidgets('zoom and translation preserve image coordinates', (
    tester,
  ) async {
    AppReportImage? saved;
    await open(tester, await _image(tester), saved: (image) => saved = image);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-100, -50, 0, 1)
      ..scaleByDouble(1.4, 1.4, 1.4, 1);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('app-report-image-mark')));
    await tester.pump();
    final box = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('app-report-image-canvas')),
    );
    final start = box.localToGlobal(
      Offset(box.size.width * .2, box.size.height * .2),
    );
    final end = box.localToGlobal(
      Offset(box.size.width * .7, box.size.height * .7),
    );
    await tester.dragFrom(start, end - start);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('app-report-image-save-marks')));
    await _wait(tester, () => saved != null);
    final rgba = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(saved!.bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    bool red(int x, int y) {
      final offset = (y * 100 + x) * 4;
      return rgba[offset] > 200 &&
          rgba[offset + 1] < 100 &&
          rgba[offset + 2] < 100;
    }

    expect(red(20, 27), isTrue);
    expect(red(70, 27), isTrue);
    expect(red(45, 12), isTrue);
    expect(red(45, 27), isFalse);
    await tester.pumpAndSettle();
  });

  final themes = {
    'בהיר': AppThemeData.light(
      AppThemeData.createColorScheme(
        AppSeedColors.defaultLight,
        Brightness.light,
      ),
      compactMenuMode: false,
    ),
    'כהה': AppThemeData.dark(
      AppThemeData.createColorScheme(
        AppSeedColors.defaultDark,
        Brightness.dark,
      ),
      compactMenuMode: false,
    ),
    'לבן': AppThemeData.light(
      AppThemeData.createColorScheme(AppSeedColors.white, Brightness.light),
      compactMenuMode: false,
      variant: AppThemeVariant.white,
    ),
  };
  for (final size in [
    const Size(360, 400),
    const Size(420, 400),
    const Size(1200, 900),
  ]) {
    for (final editable in [false, true]) {
      for (final entry in themes.entries) {
        testWidgets(
          'שם ארוך משאיר תמונה וכפתורים נגישים $size editable=$editable ${entry.key}',
          (tester) async {
            final image = await _image(
              tester,
              name: '${'W' * 176}.png',
            );
            await open(
              tester,
              image,
              size: size,
              scale: 1.3,
              editable: editable,
              theme: entry.value,
            );
            final canvas = tester.getRect(
              find.byKey(const ValueKey('app-report-image-canvas')),
            );
            expect(tester.takeException(), isNull);
            expect(canvas.width, greaterThan(0));
            expect(canvas.height, greaterThan(0));
            expect(canvas.top, greaterThanOrEqualTo(0));
            expect(canvas.bottom, lessThanOrEqualTo(size.height));
            final close = find.widgetWithText(ActionButton, 'סגור');
            expect(
              tester.getRect(close).bottom,
              lessThanOrEqualTo(size.height),
            );
            if (editable) {
              final save = find.byKey(
                const ValueKey('app-report-image-save-marks'),
              );
              expect(
                tester.getRect(save).bottom,
                lessThanOrEqualTo(size.height),
              );
              await tester.tap(
                find.byKey(const ValueKey('app-report-image-mark')),
              );
              await tester.pump();
              await tester.dragFrom(
                canvas.topLeft + canvas.size.center(Offset.zero) * .4,
                canvas.size.center(Offset.zero) * .5,
              );
              await tester.pump();
              expect(tester.widget<ActionButton>(save).onPressed, isNotNull);
            } else {
              expect(
                find.byKey(const ValueKey('app-report-image-mark')),
                findsNothing,
              );
            }
            expect(find.text(image.fileName), findsOneWidget);
          },
        );
      }
    }
  }
}

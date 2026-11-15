import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/app_report_image_sources.dart';
import 'package:otzaria/app_report/view/widgets/app_report_image_viewer.dart';
import 'package:otzaria/app_report/view/widgets/app_report_images_section.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/services/plugin_file_drop_service.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// מריץ את הזמן האמיתי (פענוח וקידוד במנוע) עד שהתנאי מתקיים.
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'timed out waiting for the engine');
}

bool _isRed(int r, int g, int b) => r > 200 && g < 100 && b < 100;

Future<Uint8List> _whitePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<({Size size, bool Function(int x, int y) isRed})> _decodeRgba(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData())!.buffer.asUint8List();
  final width = image.width;
  return (
    size: Size(width.toDouble(), image.height.toDouble()),
    isRed: (int x, int y) {
      final i = (y * width + x) * 4;
      return _isRed(rgba[i], rgba[i + 1], rgba[i + 2]);
    },
  );
}

AppReportImage _image(String name, {int size = 4}) => AppReportImage(
  bytes: Uint8List(size),
  fileName: name,
  mimeType: 'image/png',
);

class _FakeSources extends AppReportImageSources {
  _FakeSources({this.clipboard = const [], this.picked = const []});

  final List<AppReportImage> clipboard;
  final List<AppReportImage> picked;
  final List<bool> clipboardReads = [];
  BuildContext? pickerContext;

  @override
  Future<List<AppReportImage>> readClipboard({bool skipIfText = false}) async {
    clipboardReads.add(skipIfText);
    return clipboard;
  }

  @override
  Future<List<AppReportImage>> pickFiles({BuildContext? context}) async {
    pickerContext = context;
    return picked;
  }
}

void main() {
  group('mergeAppReportImages', () {
    test('מצרף עד המכסה ומדווח על העודף', () {
      final existing = List.generate(
        AppReportImage.maxCount - 1,
        (i) => _image('$i.png'),
      );
      final merged = mergeAppReportImages(existing, [
        _image('a.png'),
        _image('b.png'),
      ]);
      expect(merged.images, hasLength(AppReportImage.maxCount));
      expect(merged.rejection, AppReportImageRejection.tooMany);
    });

    test('מדלג על תמונה גדולה מדי וממשיך לשאר', () {
      final merged = mergeAppReportImages(const [], [
        _image('big.png', size: AppReportImage.maxBytes + 1),
        _image('ok.png'),
      ]);
      expect(merged.images.map((i) => i.fileName), ['ok.png']);
      expect(merged.rejection, AppReportImageRejection.tooLarge);
    });

    test('סוג התוכן לפי הסיומת', () {
      expect(AppReportImage.mimeTypeForPath(r'C:\a\b.PNG'), 'image/png');
      expect(AppReportImage.mimeTypeForPath('x.jpeg'), 'image/jpeg');
      expect(AppReportImage.mimeTypeForPath('x.GIF'), 'image/gif');
      expect(AppReportImage.mimeTypeForPath('x.webp'), isNull);
      expect(AppReportImage.mimeTypeForPath('noext'), isNull);
    });
  });

  group('AppReportImagesSection', () {
    late List<AppReportImage> images;

    Future<void> pump(
      WidgetTester tester,
      _FakeSources sources, {
      bool withTextField = false,
      int otherAttachmentBytes = 0,
    }) async {
      images = [];
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  if (withTextField)
                    const TextField(key: ValueKey('field'), autofocus: true),
                  AppReportImagesSection(
                    images: images,
                    otherAttachmentBytes: otherAttachmentBytes,
                    sources: sources,
                    onChanged: (value) => setState(() => images = value),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> replayNormalizedPaste(WidgetTester tester) async {
      // Models the framework contract after native scan-code normalization.
      // The Windows integration tests verify the actual native event conversion.
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
    }

    // כפתור ההסרה יושב בפינה העליונה, ואזור המגע שלו מגיע עד מרכז התמונה.
    Future<void> tapThumbnail(WidgetTester tester) => tester.tapAt(
      tester
              .getRect(find.byKey(const ValueKey('app-report-image-0')))
              .bottomRight -
          const Offset(12, 12),
    );

    Future<void> openViewer(WidgetTester tester) async {
      await tapThumbnail(tester);
      await tester.pump();
      await _waitFor(
        tester,
        () =>
            find
                .byKey(const ValueKey('app-report-image-canvas'))
                .evaluate()
                .isNotEmpty ||
            find.byIcon(FluentIcons.image_off_24_regular).evaluate().length > 1,
      );
      await tester.pumpAndSettle();
    }

    Future<void> markArea(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('app-report-image-mark')));
      await tester.pump();
      final box = tester.getRect(
        find.byKey(const ValueKey('app-report-image-canvas')),
      );
      await tester.dragFrom(
        box.topLeft + Offset(box.width * 0.2, box.height * 0.2),
        Offset(box.width * 0.5, box.height * 0.5),
      );
      await tester.pump();
    }

    Future<void> pressPaste(WidgetTester tester) async {
      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    testWidgets('לחיצה על האזור פותחת בחירה ומציגה את התמונות', (
      tester,
    ) async {
      final sources = _FakeSources(picked: [_image('a.png')]);
      await pump(tester, sources);
      expect(
        find.text(
          PluginFileDropService.isSupported
              ? 'הדביקו, שחררו או הקליקו לבחירת תמונה'
              : 'הדביקו או הקליקו לבחירת תמונה',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();

      expect(
        sources.pickerContext,
        tester.element(find.byType(AppReportImagesSection)),
      );
      expect(images.map((i) => i.fileName), ['a.png']);
      expect(find.byKey(const ValueKey('app-report-image-0')), findsOneWidget);
    });

    testWidgets('קיצור הדבקה מצרף את התמונה שבלוח', (tester) async {
      final sources = _FakeSources(clipboard: [_image('screenshot-1.png')]);
      await pump(tester, sources);

      await pressPaste(tester);

      expect(images.map((i) => i.fileName), ['screenshot-1.png']);
      expect(sources.clipboardReads, [false]);
    });

    testWidgets('הדבקה כשהפוקוס בשדה טקסט — נקראת רק תמונה בלי טקסט', (
      tester,
    ) async {
      final sources = _FakeSources(clipboard: [_image('shot.png')]);
      await pump(tester, sources, withTextField: true);

      await pressPaste(tester);

      expect(sources.clipboardReads, [true]);
      expect(images, hasLength(1));
    });

    for (final withTextField in [false, true]) {
      testWidgets('Shift+Insert pastes images (text focus: $withTextField)', (
        tester,
      ) async {
        final sources = _FakeSources(clipboard: [_image('insert.png')]);
        await pump(tester, sources, withTextField: withTextField);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.insert);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(images.single.fileName, 'insert.png');
        expect(sources.clipboardReads, [withTextField]);
      });

      testWidgets(
        'normalized Windows Ctrl+V pastes images once (text focus: $withTextField)',
        (tester) async {
          final sources = _FakeSources(clipboard: [_image('history.png')]);
          await pump(tester, sources, withTextField: withTextField);
          await replayNormalizedPaste(tester);
          await tester.pump();
          expect(images.single.fileName, 'history.png');
          expect(sources.clipboardReads, [withTextField]);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    for (final withAlt in [false, true]) {
      testWidgets(
        'virtual V without a paste chord never reads or pastes clipboard (Alt: $withAlt)',
        (tester) async {
          const originalText = 'Original report text';
          const clipboardText = 'This is not a paste request';
          var plainTextClipboardReads = 0;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.getData') {
                plainTextClipboardReads++;
                return {'text': clipboardText};
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final sources = _FakeSources(clipboard: [_image('unrequested.png')]);
          await pump(tester, sources, withTextField: true);
          await tester.enterText(
            find.byKey(const ValueKey('field')),
            originalText,
          );
          await tester.pump();

          if (withAlt) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          }
          try {
            // A missing scan code does not establish a clipboard-history paste.
            // This sequence deliberately has no Ctrl or Win key event.
            const physical = PhysicalKeyboardKey(0x1600000000);
            HardwareKeyboard.instance.handleKeyEvent(
              const KeyDownEvent(
                physicalKey: physical,
                logicalKey: LogicalKeyboardKey.keyV,
                timeStamp: Duration.zero,
              ),
            );
            HardwareKeyboard.instance.handleKeyEvent(
              const KeyUpEvent(
                physicalKey: physical,
                logicalKey: LogicalKeyboardKey.keyV,
                timeStamp: Duration.zero,
              ),
            );
            await tester.pump();
          } finally {
            if (withAlt) {
              await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
            }
          }
          await tester.pump();

          final editor = tester.widget<EditableText>(find.byType(EditableText));
          expect(
            {
              'imageClipboardReads': sources.clipboardReads,
              'plainTextClipboardReads': plainTextClipboardReads,
              'attachedImages': images.length,
              'reportText': editor.controller.text,
            },
            {
              'imageClipboardReads': <bool>[],
              'plainTextClipboardReads': 0,
              'attachedImages': 0,
              'reportText': originalText,
            },
            reason: 'A virtual V alone or with Alt is not a paste command.',
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets('ordinary and normalized Ctrl+V each paste text once', (
      tester,
    ) async {
      var plainTextReads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method != 'Clipboard.getData') return null;
          plainTextReads++;
          return {'text': 'טקסט'};
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final sources = _FakeSources();
      await pump(tester, sources, withTextField: true);
      await pressPaste(tester);
      await tester.pump();
      expect(find.text('טקסט'), findsOneWidget);
      expect(plainTextReads, 1);
      await replayNormalizedPaste(tester);
      await tester.pump();
      expect(find.text('טקסטטקסט'), findsOneWidget);
      expect(plainTextReads, 2);
      expect(sources.clipboardReads, [true, true]);
      expect(images, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('explicit paste image bypasses text precedence', (
      tester,
    ) async {
      final sources = _FakeSources(clipboard: [_image('explicit.png')]);
      await pump(tester, sources, withTextField: true);
      await tester.tap(find.byKey(const ValueKey('app-report-paste-image')));
      await tester.pump();
      expect(sources.clipboardReads, [false]);
      expect(images.single.fileName, 'explicit.png');
    });

    testWidgets(
      'other attachments share the budget and removal permits replacement',
      (tester) async {
        final sources = _FakeSources(picked: [_image('small.png', size: 4)]);
        await pump(
          tester,
          sources,
          otherAttachmentBytes: AppReportImage.maxTotalBytes - 4,
        );
        await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
        await tester.pump();
        expect(images, hasLength(1));
        await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
        await tester.pump();
        expect(images, hasLength(1));
        expect(
          find.text('הגודל הכולל של הצרופות מוגבל ל-20 MiB.'),
          findsOneWidget,
        );
        UiSnack.hide();
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.byKey(const ValueKey('app-report-image-remove')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
        await tester.pump();
        expect(images, hasLength(1));
      },
    );

    testWidgets('כפתור ההסרה מסיר את התמונה', (tester) async {
      await pump(tester, _FakeSources(picked: [_image('a.png')]));
      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('app-report-image-remove')));
      await tester.pump();

      expect(images, isEmpty);
      expect(find.byKey(const ValueKey('app-report-image-0')), findsNothing);
    });

    testWidgets('לחיצה על תמונה פותחת אותה בגדול, וההסרה לא פותחת', (
      tester,
    ) async {
      await pump(tester, _FakeSources(picked: [_image('a.png')]));
      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('app-report-image-remove')));
      await tester.pumpAndSettle();
      expect(find.byType(AppReportImageViewer), findsNothing);

      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();
      await openViewer(tester);

      expect(find.byType(AppReportImageViewer), findsOneWidget);
      expect(find.text('a.png'), findsOneWidget);
    });

    testWidgets('סימון אזור מחליף את התמונה ב-PNG מסומן באותו גודל', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final original = (await tester.runAsync(() => _whitePng(100, 60)))!;
      await pump(
        tester,
        _FakeSources(
          picked: [
            AppReportImage(
              bytes: original,
              fileName: 'shot.jpg',
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();
      await openViewer(tester);

      await markArea(tester);
      await tester.tap(
        find.byKey(const ValueKey('app-report-image-save-marks')),
      );
      await _waitFor(tester, () => images.single.bytes != original);
      await tester.pumpAndSettle();

      expect(find.byType(AppReportImageViewer), findsNothing);
      final marked = images.single;
      expect(marked.fileName, 'shot.png');
      expect(marked.mimeType, 'image/png');
      final pixels = (await tester.runAsync(() => _decodeRgba(marked.bytes)))!;
      expect(pixels.size, const Size(100, 60));
      // הגרירה מ-20% עד 70% ממפה למלבן x 20..70, y 12..42 בתמונה.
      expect(pixels.isRed(20, 27), isTrue);
      expect(pixels.isRed(70, 27), isTrue);
      expect(pixels.isRed(45, 12), isTrue);
      expect(pixels.isRed(45, 27), isFalse);
      expect(pixels.isRed(10, 27), isFalse);
    });

    testWidgets('תמונה מסומנת שחורגת מהמכסה לא נשמרת, והצופה נשאר פתוח', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final original = (await tester.runAsync(() => _whitePng(100, 60)))!;
      await pump(
        tester,
        _FakeSources(
          picked: [
            AppReportImage(
              bytes: original,
              fileName: 'shot.png',
              mimeType: 'image/png',
            ),
          ],
        ),
        otherAttachmentBytes: AppReportImage.maxTotalBytes - original.length,
      );
      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();
      await openViewer(tester);
      await markArea(tester);

      final save = find.byKey(const ValueKey('app-report-image-save-marks'));
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<ActionButton>(save).isLoading, isTrue);
      await _waitFor(
        tester,
        () => !tester.widget<ActionButton>(save).isLoading,
      );
      await tester.pump();

      expect(find.byType(AppReportImageViewer), findsOneWidget);
      expect(identical(images.single.bytes, original), isTrue);
      expect(tester.widget<ActionButton>(save).onPressed, isNotNull);
      UiSnack.hide();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('בטופס נעול התמונה מוצגת בלי כלי סימון', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppReportImageViewer(image: _image('a.png')),
        ),
      );
      await _waitFor(
        tester,
        () =>
            find.byIcon(FluentIcons.image_off_24_regular).evaluate().isNotEmpty,
      );

      expect(find.byKey(const ValueKey('app-report-image-mark')), findsNothing);
      expect(
        find.byKey(const ValueKey('app-report-image-save-marks')),
        findsNothing,
      );
    });

    testWidgets('חריגה מהמכסה מציגה הודעה', (tester) async {
      await pump(
        tester,
        _FakeSources(
          picked: List.generate(
            AppReportImage.maxCount + 1,
            (i) => _image('$i.png'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();

      expect(images, hasLength(AppReportImage.maxCount));
      UiSnack.hide();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'תמונה ש-Windows מציג עד 10.00 MiB מצורפת, וגדולה ממנה נדחית (issue #2839)',
      (tester) async {
        // Windows מחשב MB ב-1024×1024: 5,001,000 בתים מוצגים "4.76 MB".
        const mebibyte = 1024 * 1024;
        final dir = Directory.systemTemp.createTempSync('report_image');
        addTearDown(() => dir.deleteSync(recursive: true));
        File imageOf(String name, int size) =>
            File('${dir.path}/$name')..writeAsBytesSync([
              0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
              ...List.filled(size - 8, 0),
            ]);
        final paths = [
          imageOf('שמוצג 4.76.png', 5001000).path,
          imageOf('שמוצג 10.00.png', 10 * mebibyte).path,
          imageOf('גדול.png', 10 * mebibyte + 1).path,
        ];
        final read = await tester.runAsync(
          () => const AppReportImageSources().readPaths(paths),
        );
        await pump(tester, _FakeSources(picked: read!));

        await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
        await tester.pump();

        expect(images.map((i) => i.fileName), [
          'שמוצג 4.76.png',
          'שמוצג 10.00.png',
        ]);
        expect(find.text('תמונה גדולה מ-10 MiB לא צורפה.'), findsOneWidget);
        UiSnack.hide();
        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}

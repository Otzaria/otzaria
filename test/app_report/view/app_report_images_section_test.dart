import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/app_report_image_sources.dart';
import 'package:otzaria/app_report/view/widgets/app_report_images_section.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/services/plugin_file_drop_service.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

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

    testWidgets('כפתור ההסרה מסיר את התמונה', (tester) async {
      await pump(tester, _FakeSources(picked: [_image('a.png')]));
      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('app-report-image-remove')));
      await tester.pump();

      expect(images, isEmpty);
      expect(find.byKey(const ValueKey('app-report-image-0')), findsNothing);
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
      'תמונה ש-Windows מציג עד 5.00 MB מצורפת, וגדולה ממנה נדחית (issue #2839)',
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
          imageOf('שמוצג 5.00.png', 5 * mebibyte).path,
          imageOf('גדול.png', 5 * mebibyte + 1).path,
        ];
        final read = await tester.runAsync(
          () => const AppReportImageSources().readPaths(paths),
        );
        await pump(tester, _FakeSources(picked: read!));

        await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
        await tester.pump();

        expect(images.map((i) => i.fileName), [
          'שמוצג 4.76.png',
          'שמוצג 5.00.png',
        ]);
        expect(find.text('תמונה גדולה מ-5 MB לא צורפה.'), findsOneWidget);
        UiSnack.hide();
        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}

// חיצי הניווט נמצאים בסרגל אם כולם נכנסים בו, ואחרת בתפריט "עוד".
// בכל רוחב הם מופיעים במקום אחד בדיוק.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';
import 'small_screens_fixture.dart';

Future<void> _loadFonts() async {
  await loadGoldenFonts();
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
  await roboto.load();
}

/// PDF של עמוד אחד, בנוי ביד (ההיסטים מחושבים).
String _pdfPath() {
  final dir = Directory.systemTemp.createTempSync('otzaria-reader-nav-pdf-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // קובץ שעדיין פתוח נמחק עם תיקיית הזמניים של המערכת.
    }
  });
  final objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 595] /Contents 4 0 R >>',
    '<< /Length 0 >>\nstream\n\nendstream',
  ];
  final b = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(latin1.encode(b.toString()).length);
    b.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = latin1.encode(b.toString()).length;
  b.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write(
    'trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  final f = File('${dir.path}/book.pdf')..writeAsBytesSync(latin1.encode('$b'));
  return f.path;
}

Future<void> _pumpReader(
  WidgetTester tester,
  Size size, {
  SmallScreen screen = SmallScreen.reader,
}) async {
  await Settings.init(cacheProvider: MemorySettingsCache());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  String? pdf;
  if (screen == SmallScreen.pdf) {
    final originalModulePath = Pdfrx.pdfiumModulePath;
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModulePath);
    final pp = Directory.systemTemp.createTempSync('otzaria-reader-nav-pp-');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => pp.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      ),
    );
    pdf = await tester.runAsync(() async => _pdfPath());
  }
  final wrap = smallScreenProviders(
    tester,
    screen: screen,
    size: size,
    pdfPath: pdf,
  );
  final cs = AppThemeData.createColorScheme(
    AppSeedColors.defaultLight,
    Brightness.light,
  );
  await tester.pumpWidget(
    wrap(
      MaterialApp(
        localizationsDelegates: const [
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('he', 'IL')],
        locale: const Locale('he', 'IL'),
        theme: AppThemeData.light(
          cs,
          compactMenuMode: AppDensity.isSmallWindow(size),
        ),
        home: const MainWindowScreen(),
      ),
    ),
  );
  if (screen == SmallScreen.pdf) {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _readerArrows = [
  'הדף/פרק הקודם',
  'הקטע הקודם',
  'הקטע הבא',
  'הדף/פרק הבא',
];
const _pdfArrows = ['הקודם', 'הבא'];

/// האם החיצים בסרגל — ובדיקה שההחלטה היא לפי הרוחב שהמרכז קיבל בפועל, ושהם
/// אחרי פתיחת "עוד" במקום אחד בדיוק.
Future<bool> _arrowsInBar(WidgetTester tester, List<String> arrows) async {
  final inBar = arrows
      .where((t) => find.byTooltip(t).evaluate().isNotEmpty)
      .length;
  expect(inBar, anyOf(0, arrows.length), reason: 'כל החיצים או אף אחד');
  final center = tester.getSize(find.byType(ReaderNavCenter)).width;
  final isCompact = AppDensity.of(
    tester.element(find.byType(ReaderNavCenter)),
  ).isCompact;
  expect(
    inBar > 0,
    ReaderNavCenter.navFits(center, isCompact: isCompact),
    reason: 'center=$center',
  );

  await tester.tap(find.byTooltip('עוד פעולות').last);
  await _settle(tester);
  for (final tooltip in arrows) {
    expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
  }
  expect(tester.takeException(), isNull);
  return inBar > 0;
}

void main() {
  setUpAll(_loadFonts);

  // בטלפון לאורך, ובחלון של 480, הפעולות שבצד לוקחות את הסרגל, ולמרכז
  // נשאר פחות מארבעה כפתורים.
  for (final size in const [Size(360, 640), Size(390, 844), Size(480, 800)]) {
    testWidgets(
      'קורא ${size.width.toInt()}: אין מקום לארבעה — בתפריט "עוד", והכותרת במרכז',
      (tester) async {
        await _pumpReader(tester, size);
        // הכותרת (המקום בספר) קיבלה את המרכז ולא רוחב 0.
        final title = find.textContaining('פרק א').first;
        expect(tester.getSize(title).width, greaterThan(40));
        expect(await _arrowsInBar(tester, _readerArrows), isFalse);
      },
    );
  }

  // חלון 675 עם פס הניווט: סרגל של 600. ארבעת החיצים נכנסים, וקודמים לכותרת.
  for (final size in const [Size(675, 640), Size(844, 390), Size(1024, 600)]) {
    testWidgets(
      'קורא ${size.width.toInt()}×${size.height.toInt()}: החיצים נכנסים — בסרגל',
      (tester) async {
        await _pumpReader(tester, size);
        expect(await _arrowsInBar(tester, _readerArrows), isTrue);
      },
    );
  }

  for (final (size, inBar) in const [
    (Size(360, 640), false),
    (Size(480, 800), false),
    (Size(1024, 600), true),
  ]) {
    testWidgets(
      'PDF ${size.width.toInt()}×${size.height.toInt()}: '
      '${inBar ? 'בסרגל' : 'בתפריט "עוד"'}',
      (tester) async {
        await _pumpReader(tester, size, screen: SmallScreen.pdf);
        expect(await _arrowsInBar(tester, _pdfArrows), inBar);
      },
    );
  }
}

/// רתמת רינדור ויזואלית: מריצה את המנוע על ה-fixtures, מרנדרת עמודים אמיתיים
/// ושומרת PNG לבדיקת עין. רצה רק כש-TIKKUN_VISUAL=1 (לא ב-CI).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_width_measurer.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';

import '../support/tikkun_fixtures.dart';

final bool _enabled = Platform.environment['TIKKUN_VISUAL'] == '1';

const String _outDir =
    r'C:\Users\User\AppData\Local\Temp\claude'
    r'\C--otzaria\4c81a4d9-91e3-40aa-9752-6a3a0b621cfc\scratchpad\visual';

/// גובה גדול דיו לעמוד שלם: כשהתוכן חורג מהמסך פריסת הרשימה נהיית איטית מאוד.
const Size _surface = Size(1400, 3400);
const double _pixelRatio = 2;

const Map<String, String> _fontFiles = {
  'AshkenaziStam': 'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
  'SefardiStam': 'fonts/tikkun_korim/Sefardi-Stam.ttf',
  'FrankRuhlCLM': 'fonts/FrankRuehlCLM-Medium.ttf',
};

final GlobalKey _captureKey = GlobalKey();

Future<void> _loadFonts() async {
  for (final entry in _fontFiles.entries) {
    final bytes = await File(entry.value).readAsBytes();
    await (FontLoader(
      entry.key,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

Future<void> _capture(WidgetTester tester, String name) =>
    // צילום חייב runAsync: toImage ממתין לתהליך הראסטר האמיתי.
    tester.runAsync(() => _captureNow(name));

Future<void> _captureNow(String name) async {
  final boundary =
      _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: _pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  Directory(_outDir).createSync(recursive: true);
  File('$_outDir\\$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('saved $name.png');
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<TikkunLine> lines,
  TikkunSettings settings = const TikkunSettings(),
  String? title,
  String? subtitle,
  Size surface = _surface,
}) async {
  await tester.binding.setSurfaceSize(surface);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('he', 'IL'),
      theme: ThemeData(fontFamily: 'FrankRuhlCLM'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: RepaintBoundary(
          key: _captureKey,
          child: Scaffold(
            body: ReaderPage(
              lines: lines,
              settings: settings,
              hideStam: settings.hideStam,
              hideNikud: settings.hideNikud,
              headerTitle: title,
              headerSubtitle: subtitle,
            ),
          ),
        ),
      ),
    ),
  );
  // pumpAndSettle לא נסגר על רשימת השורות; שני פריימים מספיקים לפריסה מלאה.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// מספר השורות המרבי לצילום אחד — מעבר לכך פריסת הרשימה נתקעת לדקות ארוכות.
const int _maxRowsPerShot = 28;

/// מצלם עמוד שלם, בחלקים של [_maxRowsPerShot] שורות.
Future<void> _capturePage(
  WidgetTester tester,
  String name,
  List<TikkunLine> lines, {
  TikkunSettings settings = const TikkunSettings(),
  String? title,
  Size surface = _surface,
}) async {
  for (
    var start = 0, part = 1;
    start < lines.length;
    start += _maxRowsPerShot, part++
  ) {
    final end = (start + _maxRowsPerShot).clamp(0, lines.length);
    await _pumpPage(
      tester,
      lines: lines.sublist(start, end),
      settings: settings,
      title: title,
      subtitle: lines.length > _maxRowsPerShot ? 'שורות $start-$end' : null,
      surface: surface,
    );
    await _capture(
      tester,
      lines.length > _maxRowsPerShot ? '${name}_$part' : name,
    );
  }
}

/// אינדקס האסימון שפותח מקטע מיוחד מזוהה.
int _sectionTokenIdx(List<TikkunToken> tokens, String sectionId) =>
    tokens.indexWhere(
      (t) =>
          t.type == TikkunTokenType.specialStart && t.section?.id == sectionId,
    );

/// אינדקס השורה המיוחדת הראשונה שאחרי אסימון נתון.
int _firstSpecialLineAfter(List<TikkunLine> lines, int tokenIdx) {
  var reached = false;
  for (var i = 0; i < lines.length; i++) {
    final st = lines[i].startTokenIdx;
    if (st >= tokenIdx) reached = true;
    if (reached && lines[i].isSpecial) return i;
  }
  return -1;
}

int _lastSpecialLineOfRun(List<TikkunLine> lines, int firstIdx) {
  var last = firstIdx;
  for (var i = firstIdx; i < lines.length; i++) {
    if (lines[i].isSpecial) {
      last = i;
    } else if (i - last > 2) {
      break;
    }
  }
  return last;
}

/// חלון שורות סביב מקטע מיוחד — "עמוד" לספר שאינו חלק מהתורה.
List<TikkunLine> _windowAround(List<TikkunLine> lines, int from, int to) =>
    lines.sublist(
      (from - 3).clamp(0, lines.length),
      (to + 4).clamp(0, lines.length),
    );

int _pageIdxWithLine(List<TikkunPage> pages, int lineIdx) => pages.indexWhere(
  (p) => lineIdx >= p.startLineIdx && lineIdx <= p.endLineIdx,
);

void main() {
  late Map<String, String> raw;
  late ProcessedTorah torah;
  late List<TikkunPage> ramah;
  late StamWidthModel widths;

  // קלט/פלט אמיתי נתקע בתוך ה-FakeAsync של testWidgets — כאן הוא רץ באמת.
  setUpAll(() async {
    if (!_enabled) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    widths = measureStamWidthModel(const TikkunSettings().stamFontFamily);
    raw = {for (final id in fixtureBookNames.keys) id: readFixture(id)};
    torah = processTorah({
      for (final id in TikkunData.booksOrder) id: raw[id]!,
    }, widths);
    ramah = buildPages(torah, 'ramah');
    // ignore: avoid_print
    print('ramah pages: ${ramah.length} torah lines: ${torah.allLines.length}');
  });

  // כל המקרים בבדיקה אחת: פירוק העץ בסוף testWidgets עולה כעשר דקות.
  testWidgets('רתמת רינדור — שמירת PNG לכל המקרים', (tester) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    List<TikkunLine> pageOfLine(int lineIdx) {
      final pageIdx = _pageIdxWithLine(ramah, lineIdx);
      // ignore: avoid_print
      print('line=$lineIdx page=$pageIdx');
      return pageIdx >= 0
          ? ramah[pageIdx].lines
          : _windowAround(
              torah.allLines,
              lineIdx,
              _lastSpecialLineOfRun(torah.allLines, lineIdx),
            );
    }

    List<TikkunLine> torahSection(String sectionId) {
      final tokenIdx = _sectionTokenIdx(torah.tokens, sectionId);
      expect(tokenIdx, greaterThan(-1), reason: '$sectionId token');
      final lineIdx = _firstSpecialLineAfter(torah.allLines, tokenIdx);
      expect(lineIdx, greaterThan(-1), reason: '$sectionId line');
      // ignore: avoid_print
      print('$sectionId: token=$tokenIdx');
      return pageOfLine(lineIdx);
    }

    List<TikkunLine> bookSection(String bookId, String sectionId) {
      final tokens = tokenizeBook(raw[bookId]!, fixtureBookNames[bookId]!);
      final lines = paginateAllTokens(tokens, widths);
      final tokenIdx = _sectionTokenIdx(tokens, sectionId);
      expect(tokenIdx, greaterThan(-1), reason: '$sectionId token');
      final first = _firstSpecialLineAfter(lines, tokenIdx);
      final last = _lastSpecialLineOfRun(lines, first);
      // ignore: avoid_print
      print('$sectionId: token=$tokenIdx lines=$first..$last');
      return _windowAround(lines, first, last);
    }

    final page1 = ramah.first.lines;

    await _capturePage(tester, '01_bereshit_page1', page1, title: 'בראשית');

    await _capturePage(
      tester,
      '02_setuma',
      pageOfLine(
        torah.allLines.indexWhere((l) => l.layout == LineLayout.setuma),
      ),
      title: 'רווח סתומה',
    );

    // רווח הפתיחה (BIGGAP) מופיע רק בהפטרות, לא ברצף התורה.
    final haftarah = TikkunData.haftarot.firstWhere(
      (h) => h.id == 'p:Bereshit',
    );
    final haftarahLines = buildHaftarahLines(haftarah, 'ashkenaz', {
      fixtureBookNames['yeshayahu']!: tokenizeBook(
        raw['yeshayahu']!,
        fixtureBookNames['yeshayahu']!,
      ),
    }, widths);
    final torahBigGap = torah.allLines.indexWhere(
      (l) => l.words.any((w) => w.isBigGap),
    );
    final haftarahBigGap = haftarahLines.indexWhere(
      (l) =>
          l.words.any((w) => w.isBigGap) || l.layout == LineLayout.setumaStart,
    );
    // ignore: avoid_print
    print('bigGap torah=$torahBigGap haftarah=$haftarahBigGap');
    await _capturePage(
      tester,
      '03_setuma_start',
      haftarahLines.sublist(0, haftarahLines.length.clamp(0, 28)),
      title: 'פתיחת הפטרה',
    );

    await _capturePage(
      tester,
      '04_shirat_hayam',
      torahSection('shirat_hayam'),
      title: 'שירת הים',
    );

    await _capturePage(
      tester,
      '05_shirat_haazinu',
      torahSection('shirat_haazinu'),
      title: 'שירת האזינו',
    );

    await _capturePage(
      tester,
      '06_shirat_devorah',
      bookSection('shoftim', 'shirat_devorah'),
      title: 'שירת דבורה',
    );

    await _capturePage(
      tester,
      '07_bnei_haman',
      bookSection('esther', 'aseret_bnei_haman'),
      title: 'עשרת בני המן',
    );

    await _capturePage(
      tester,
      '08_hide_nikud',
      page1,
      settings: const TikkunSettings(hideNikud: true),
      title: 'ללא מנוקד',
    );

    await _capturePage(
      tester,
      '09_hide_stam',
      page1,
      settings: const TikkunSettings(hideStam: true),
      title: 'ללא סת"ם',
    );

    await _capturePage(
      tester,
      '10_swap_columns',
      page1,
      settings: const TikkunSettings(swapColumns: true),
      title: 'טורים מוחלפים',
    );

    // גודל הגופן נגזר מרוחב העמוד בלבד.
    await _capturePage(
      tester,
      '11_narrow_width',
      page1,
      title: 'רוחב צר',
      surface: const Size(820, 3400),
    );

    await _capturePage(
      tester,
      '12_line_spacing',
      page1,
      settings: const TikkunSettings(lineSpacing: 2),
      title: 'ריווח 2.0',
    );
  }, skip: !_enabled);
}

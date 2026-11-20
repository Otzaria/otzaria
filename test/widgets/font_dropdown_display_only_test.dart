import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/file/native_font_families.dart';
import 'package:otzaria/utils/file/user_font_importer.dart';
import 'package:otzaria/widgets/misc/font_dropdown_field.dart';
import 'package:otzaria/widgets/misc/font_import_flow.dart';

class _FakeNative implements NativeFontFamilySource {
  @override
  Future<List<NativeFontFamily>> hebrewFamilies() async => const [
    NativeFontFamily('Arial Hebrew', supportsTaamim: false),
    NativeFontFamily('Times New Roman'),
  ];
}

class _FakePicker implements FontFilePicker {
  _FakePicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> pickFontFile(BuildContext context) async {
    calls++;
    return path;
  }
}

/// מייבא מזויף: מחזיר תוצאה קבועה ורושם מה התבקש.
UserFontImporter _importerReturning(
  UserFontImportResult result,
  List<String> seen,
) => _FakeImporter(result, seen);

class _FakeImporter extends UserFontImporter {
  _FakeImporter(this.result, this.seen)
    : super(
        directory: '/unused',
        inspect: _noInspect,
        onChanged: _noChange,
      );

  final UserFontImportResult result;
  final List<String> seen;

  static Future<List<String>> _noInspect(String path) async => const [];
  static Future<void> _noChange() async {}

  @override
  Future<UserFontImportResult> importFile(String sourcePath) async {
    seen.add(sourcePath);
    return result;
  }
}

Widget _app(ValueChanged<String> onChanged) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 340,
        child: FontDropdownField(
          value: AppFonts.defaultFont,
          onChanged: onChanged,
        ),
      ),
    ),
  ),
);

void main() {
  final onIos = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() {
    AppFonts.debugResetSystemFontsCache();
    AppFonts.nativeFontFamilySource = _FakeNative();
    AppFonts.debugScanAll = () async => const SystemFontScanResult.empty();
  });

  tearDown(() {
    AppFonts.debugResetSystemFontsCache();
    AppFonts.debugScanAll = null;
    AppFonts.nativeFontFamilySource = const ChannelNativeFontFamilySource();
    FontImportFlow.debugReset();
  });

  Future<void> openAndSearch(WidgetTester tester, String query) async {
    await tester.tap(find.byType(FontDropdownField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, query);
    await tester.pumpAndSettle();
  }

  group('גופנים לתצוגה בלבד', () {
    testWidgets('שורת גופן מערכת מסומנת "לתצוגה בלבד" ועליה הסבר', (
      tester,
    ) async {
      await tester.pumpWidget(_app((_) {}));
      await tester.pumpAndSettle();
      await openAndSearch(tester, 'Arial');

      expect(find.text('Arial Hebrew'), findsWidgets);
      expect(find.text('לתצוגה בלבד'), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('לתצוגה בלבד'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('הדפסה'));
      expect(tooltip.message, contains('PDF'));
    }, variant: onIos);

    testWidgets('גופן מובנה לא מסומן', (tester) async {
      await tester.pumpWidget(_app((_) {}));
      await tester.pumpAndSettle();
      await openAndSearch(tester, 'טינוס');
      expect(find.text('טינוס'), findsWidgets);
      expect(find.text('לתצוגה בלבד'), findsNothing);
    }, variant: onIos);

    testWidgets('התצוגה המקדימה של גופן מערכת היא בשמו, בלי קידומת הבידוד', (
      tester,
    ) async {
      await tester.pumpWidget(_app((_) {}));
      await tester.pumpAndSettle();
      await openAndSearch(tester, 'Arial');

      final families = tester
          .widgetList<Text>(find.text('Arial Hebrew'))
          .map((t) => t.style?.fontFamily)
          .toSet();
      expect(families, contains('Arial Hebrew'));
    }, variant: onIos);

    testWidgets('בחירת גופן מערכת מחזירה את שמו', (tester) async {
      String? chosen;
      await tester.pumpWidget(_app((v) => chosen = v));
      await tester.pumpAndSettle();
      await openAndSearch(tester, 'Arial');
      await tester.tap(find.text('Arial Hebrew').last);
      await tester.pumpAndSettle();
      expect(chosen, 'Arial Hebrew');
    }, variant: onIos);

    testWidgets('בשאר הפלטפורמות אין סימון ואין פעולת ייבוא', (tester) async {
      await tester.pumpWidget(_app((_) {}));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FontDropdownField));
      await tester.pumpAndSettle();
      expect(find.text('לתצוגה בלבד'), findsNothing);
      expect(find.text('הוסף גופן מקובץ…'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('ייבוא גופן מקובץ', () {
    testWidgets('ב-iOS יש שורה "הוסף גופן מקובץ…" בראש הרשימה', (tester) async {
      await tester.pumpWidget(_app((_) {}));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FontDropdownField));
      await tester.pumpAndSettle();
      expect(find.text('הוסף גופן מקובץ…'), findsOneWidget);
    }, variant: onIos);

    testWidgets('ביטול הבורר: לא מייבאים ולא משנים בחירה', (tester) async {
      final picker = _FakePicker(null);
      final seen = <String>[];
      FontImportFlow.picker = picker;
      FontImportFlow.importerFactory = () => _importerReturning(
        const UserFontImportResult(UserFontImportStatus.imported, ['X']),
        seen,
      );
      String? chosen;
      await tester.pumpWidget(_app((v) => chosen = v));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FontDropdownField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הוסף גופן מקובץ…'));
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      expect(seen, isEmpty);
      expect(chosen, isNull);
    }, variant: onIos);

    testWidgets('ייבוא מוצלח בוחר את המשפחה שיובאה', (tester) async {
      final seen = <String>[];
      FontImportFlow.picker = _FakePicker('/tmp/picked/Frank.ttf');
      FontImportFlow.importerFactory = () => _importerReturning(
        const UserFontImportResult(UserFontImportStatus.imported, [
          'Frank Ruehl',
          'Frank Ruehl Bold',
        ]),
        seen,
      );
      String? chosen;
      await tester.pumpWidget(_app((v) => chosen = v));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FontDropdownField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הוסף גופן מקובץ…'));
      await tester.pumpAndSettle();

      expect(seen, ['/tmp/picked/Frank.ttf']);
      expect(chosen, 'Frank Ruehl');
    }, variant: onIos);

    for (final status in [
      UserFontImportStatus.notAFont,
      UserFontImportStatus.noHebrew,
      UserFontImportStatus.tooLarge,
      UserFontImportStatus.failed,
    ]) {
      testWidgets('ייבוא שנכשל ($status): הבחירה לא משתנה', (tester) async {
        FontImportFlow.picker = _FakePicker('/tmp/picked/x.ttf');
        FontImportFlow.importerFactory = () =>
            _importerReturning(UserFontImportResult(status), []);
        String? chosen;
        await tester.pumpWidget(_app((v) => chosen = v));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FontDropdownField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('הוסף גופן מקובץ…'));
        await tester.pumpAndSettle();
        expect(chosen, isNull);
      }, variant: onIos);
    }

    testWidgets('בלי תיקיית משתמש (אין מייבא): כשל נקי, בלי קריאה לבורר', (
      tester,
    ) async {
      final picker = _FakePicker('/tmp/x.ttf');
      FontImportFlow.picker = picker;
      FontImportFlow.importerFactory = () => null;
      String? chosen;
      await tester.pumpWidget(_app((v) => chosen = v));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FontDropdownField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הוסף גופן מקובץ…'));
      await tester.pumpAndSettle();
      expect(picker.calls, 0);
      expect(chosen, isNull);
    }, variant: onIos);

    testWidgets('ההודעות: לכל סטטוס יש טקסט, ובהצלחה גם שם הגופן', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      for (final status in UserFontImportStatus.values) {
        final message = fontImportMessage(
          context,
          UserFontImportResult(status, const ['Frank Ruehl']),
        );
        expect(message, isNotEmpty, reason: '$status');
        expect(
          message.contains('Frank Ruehl'),
          status == UserFontImportStatus.imported ||
              status == UserFontImportStatus.alreadyImported,
          reason: '$status',
        );
      }
    });
  });
}

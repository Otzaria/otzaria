import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/file/native_font_families.dart';

class _FakeSource implements NativeFontFamilySource {
  _FakeSource(this.families);

  List<NativeFontFamily> families;
  int calls = 0;
  Object? error;

  @override
  Future<List<NativeFontFamily>> hebrewFamilies() async {
    calls++;
    if (error != null) throw error!;
    return families;
  }
}

Uint8List _font(String name) => File('fonts/$name').readAsBytesSync();

/// סריקה שבה משפחה אחת שיובאה מקובץ בתיקיית המשתמש.
SystemFontScanResult _scanWith(String family) {
  final faces = SystemFontFamilyFaces(
    family: family,
    regularPath: '/user/$family.ttf',
    regularWeight: 400,
  );
  return SystemFontScanResult(
    fonts: [FontInfo(value: family, label: family)],
    families: {family: faces},
    allFamilies: {family: faces},
    aliases: const {},
  );
}

void main() {
  late _FakeSource source;
  const arial = NativeFontFamily('Arial Hebrew', supportsTaamim: false);
  const times = NativeFontFamily('Times New Roman');
  final onIos = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() {
    AppFonts.debugResetSystemFontsCache();
    source = _FakeSource([times, arial]);
    AppFonts.nativeFontFamilySource = source;
    AppFonts.debugScanAll = () async => const SystemFontScanResult.empty();
  });

  tearDown(() {
    AppFonts.debugResetSystemFontsCache();
    AppFonts.debugScanAll = null;
    AppFonts.nativeFontFamilySource = const ChannelNativeFontFamilySource();
  });

  group('iOS', () {
    testWidgets(
      'שמות המערכת מצטרפים לרשימה אחרי החימום, ממוינים, לתצוגה בלבד',
      (tester) async {
        expect(AppFonts.systemFontsReady, isFalse);
        final bundledOnly = AppFonts.availableFonts.length;
        await AppFonts.warmUpSystemFontsCache();
        expect(AppFonts.systemFontsReady, isTrue);

        final fonts = AppFonts.availableFonts;
        expect(fonts.length, bundledOnly + 2);
        final native = fonts.where((f) => f.displayOnly).toList();
        expect(native.map((f) => f.value), ['Arial Hebrew', 'Times New Roman']);
        expect(native.map((f) => f.label), ['Arial Hebrew', 'Times New Roman']);
        expect(fonts.where((f) => !f.displayOnly).length, bundledOnly);
        expect(source.calls, 1);
      },
      variant: onIos,
    );

    testWidgets(
      'גופן שיובא כקובץ גובר על אותו שם מהמערכת, ולא מוצג פעמיים',
      (tester) async {
        const imported = 'MyUserFont';
        source.families = [NativeFontFamily(imported), arial];
        AppFonts.debugScanAll = () async => _scanWith(imported);
        await AppFonts.warmUpSystemFontsCache();

        final withName = AppFonts.availableFonts.where(
          (f) => f.value == imported,
        );
        expect(withName.length, 1);
        expect(withName.single.displayOnly, isFalse);
        expect(AppFonts.isDisplayOnly(imported), isFalse);
        expect(AppFonts.isDisplayOnly('Arial Hebrew'), isTrue);
      },
      variant: onIos,
    );

    testWidgets('שם של גופן מובנה לא מתווסף שוב מהמערכת', (tester) async {
      source.families = [const NativeFontFamily('Tinos'), arial];
      await AppFonts.warmUpSystemFontsCache();
      expect(
        AppFonts.availableFonts.where((f) => f.value == 'Tinos').length,
        1,
      );
      expect(AppFonts.isDisplayOnly('Tinos'), isFalse);
    }, variant: onIos);

    testWidgets('גופן לתצוגה בלבד מצויר בשמו, בלי קידומת הבידוד', (
      tester,
    ) async {
      await AppFonts.warmUpSystemFontsCache();
      expect(AppFonts.renderFontFamily('Arial Hebrew'), 'Arial Hebrew');
      // גופן שלא ידוע לא עובר ללא קידומת: הוא נופל לגופן ברירת המחדל כמו תמיד.
      expect(
        AppFonts.renderFontFamily('Unknown Family'),
        startsWith('OtzariaSystem:'),
      );
    }, variant: onIos);

    testWidgets('גופן מקובץ משתמש בקידומת הבידוד כמו בשאר הפלטפורמות', (
      tester,
    ) async {
      const imported = 'MyUserFont';
      source.families = [NativeFontFamily(imported)];
      AppFonts.debugScanAll = () async => _scanWith(imported);
      await AppFonts.warmUpSystemFontsCache();
      expect(AppFonts.renderFontFamily(imported), 'OtzariaSystem:$imported');
    }, variant: onIos);

    testWidgets(
      'לגופן לתצוגה בלבד אין בתים: הוא לא במפות שהדפסה, PDF ותוספים קוראים',
      (tester) async {
        await AppFonts.warmUpSystemFontsCache();
        expect(AppFonts.systemFamilyFaces('Arial Hebrew'), isNull);
        expect(AppFonts.pluginSystemFamilyFaces('Arial Hebrew'), isNull);
        expect(
          AppFonts.pluginSystemFamilyFacesByCompactName('Arial Hebrew'),
          isNull,
        );
        expect(
          AppFonts.installedFamilies()?.map((f) => f.family) ?? const [],
          isNot(contains('Arial Hebrew')),
        );
      },
      variant: onIos,
    );

    testWidgets('fontsWithFiles (הרשימה להדפסה) לא כוללת גופני תצוגה בלבד', (
      tester,
    ) async {
      await AppFonts.warmUpSystemFontsCache();
      final printable = AppFonts.fontsWithFiles.map((f) => f.value);
      expect(printable, isNot(contains('Arial Hebrew')));
      expect(printable, isNot(contains('Times New Roman')));
      expect(printable, contains(AppFonts.defaultFont));
    }, variant: onIos);

    testWidgets(
      'דגל הטעמים מהמערכת נשמר: בטקסט עם טעמים נופלים לגופן ברירת המחדל',
      (tester) async {
        await AppFonts.warmUpSystemFontsCache();
        expect(AppFonts.familySupportsTaamim('Arial Hebrew'), isFalse);
        expect(AppFonts.familySupportsTaamim('Times New Roman'), isTrue);
        expect(
          AppFonts.taamimSafeFontFamily('Arial Hebrew', 'בְּרֵאשִׁ֖ית'),
          AppFonts.defaultFont,
        );
        expect(
          AppFonts.taamimSafeFontFamily('Arial Hebrew', 'בראשית'),
          'Arial Hebrew',
        );
      },
      variant: onIos,
    );

    testWidgets('ensureFontLoaded של גופן לתצוגה בלבד מסתיים בלי שגיאה', (
      tester,
    ) async {
      await AppFonts.ensureFontLoaded('Arial Hebrew');
      expect(AppFonts.isDisplayOnly('Arial Hebrew'), isTrue);
    }, variant: onIos);

    testWidgets('כשל בערוץ: הרשימה נשארת מובנית ומוכנה, בלי זריקה', (
      tester,
    ) async {
      source.error = StateError('channel down');
      final bundledOnly = AppFonts.availableFonts.length;
      await AppFonts.warmUpSystemFontsCache();
      expect(AppFonts.systemFontsReady, isTrue);
      expect(AppFonts.availableFonts.length, bundledOnly);
    }, variant: onIos);

    testWidgets('רענון הסריקה מוסיף גופן שיובא, בלי לשאול את המערכת שוב', (
      tester,
    ) async {
      await AppFonts.warmUpSystemFontsCache();
      const imported = 'MyUserFont';
      expect(
        AppFonts.availableFonts.map((f) => f.value),
        isNot(contains(imported)),
      );

      AppFonts.debugScanAll = () async => _scanWith(imported);
      await AppFonts.refreshSystemFonts();

      expect(AppFonts.availableFonts.map((f) => f.value), contains(imported));
      expect(AppFonts.systemFamilyFaces(imported), isNotNull);
      expect(AppFonts.isDisplayOnly('Arial Hebrew'), isTrue);
      expect(source.calls, 1);
    }, variant: onIos);

    test(
      'hebrewFamiliesInFile מחזיר את המשפחות העבריות בקובץ ורק אותן',
      () async {
        final tinos = AppFonts.debugFontFamilyName(_font('Tinos-Regular.ttf'));
        expect(await AppFonts.hebrewFamiliesInFile('fonts/Tinos-Regular.ttf'), [
          tinos,
        ]);
        expect(
          await AppFonts.hebrewFamiliesInFile('fonts/does-not-exist.ttf'),
          isEmpty,
        );
        final notFont = File(
          '${Directory.systemTemp.path}/otzaria_not_font.ttf',
        )..writeAsBytesSync(List.filled(64, 7));
        addTearDown(notFont.deleteSync);
        expect(await AppFonts.hebrewFamiliesInFile(notFont.path), isEmpty);
      },
    );
  });

  group('פלטפורמות אחרות', () {
    testWidgets(
      'ב-Windows הערוץ הנייטיבי לא נשאל ושום גופן לא מסומן לתצוגה בלבד',
      (tester) async {
        await AppFonts.warmUpSystemFontsCache();
        expect(source.calls, 0);
        expect(AppFonts.availableFonts.where((f) => f.displayOnly), isEmpty);
        expect(AppFonts.isDisplayOnly('Arial Hebrew'), isFalse);
        expect(
          AppFonts.renderFontFamily('Arial Hebrew'),
          startsWith('OtzariaSystem:'),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('באנדרואיד גם לא', (tester) async {
      await AppFonts.warmUpSystemFontsCache();
      expect(source.calls, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}

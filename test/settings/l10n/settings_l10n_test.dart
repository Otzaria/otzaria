import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

import '../../../tool/src/settings_l10n_generator.dart';

void main() {
  group('SettingsLanguage', () {
    test('עברית היא שפת המקור ולכן אין לה קטלוג', () {
      expect(SettingsLanguage.source, SettingsLanguage.hebrew);
      expect(
        kSettingsCatalogs.containsKey(SettingsLanguage.hebrew.code),
        isFalse,
      );
    });

    test('לכל שפה שאינה המקור יש קטלוג', () {
      for (final language in SettingsLanguage.values) {
        if (language == SettingsLanguage.source) continue;
        expect(
          kSettingsCatalogs.containsKey(language.code),
          isTrue,
          reason:
              'חסר lib/settings/l10n/settings_${language.code}.arb '
              'עבור ${language.label}',
        );
      }
    });

    test('כל קטלוג מתאים לשפה מוכרת', () {
      for (final code in kSettingsCatalogs.keys) {
        expect(
          SettingsLanguage.fromCode(code),
          isNotNull,
          reason: 'קיים קטלוג "$code" ללא ערך תואם ב-SettingsLanguage',
        );
      }
    });

    test('כיווני הכתיבה מוגדרים נכון', () {
      expect(SettingsLanguage.hebrew.textDirection, TextDirection.rtl);
      expect(SettingsLanguage.english.textDirection, TextDirection.ltr);
    });

    test('קוד שמור מתורגם לשפה; ערך חסר או לא מוכר מחזיר null', () {
      expect(SettingsLanguage.fromCode('en'), SettingsLanguage.english);
      expect(SettingsLanguage.fromCode('he'), SettingsLanguage.hebrew);
      expect(SettingsLanguage.fromCode(null), isNull);
      expect(SettingsLanguage.fromCode('fr'), isNull);
      expect(SettingsLanguage.fromCode(kSettingsLanguageSystemCode), isNull);
    });
  });

  group('resolveSettingsLanguage', () {
    test('ברירת המחדל היא זיהוי אוטומטי', () {
      expect(kDefaultSettingsLanguageCode, kSettingsLanguageSystemCode);
    });

    test('בחירה מפורשת גוברת על שפת המערכת', () {
      expect(
        resolveSettingsLanguage('he', systemLocale: const Locale('en', 'US')),
        SettingsLanguage.hebrew,
      );
      expect(
        resolveSettingsLanguage('en', systemLocale: const Locale('he', 'IL')),
        SettingsLanguage.english,
      );
    });

    test('אוטומטי: מערכת בעברית מניבה עברית', () {
      expect(
        resolveSettingsLanguage(
          kSettingsLanguageSystemCode,
          systemLocale: const Locale('he', 'IL'),
        ),
        SettingsLanguage.hebrew,
      );
    });

    test('אוטומטי: הקוד הישן iw מזוהה גם הוא כעברית', () {
      for (final code in ['iw', 'IW']) {
        expect(
          resolveSettingsLanguage(
            kSettingsLanguageSystemCode,
            systemLocale: Locale(code),
          ),
          SettingsLanguage.hebrew,
          reason: 'שפת מערכת "$code"',
        );
      }
    });

    test('אוטומטי: שפה שאינה נתמכת נופלת לאנגלית', () {
      for (final code in ['fr', 'ru', 'ar', 'yi']) {
        expect(
          resolveSettingsLanguage(
            kSettingsLanguageSystemCode,
            systemLocale: Locale(code),
          ),
          SettingsLanguage.english,
          reason: 'שפת מערכת "$code"',
        );
      }
    });

    test('קוד שנשמר בגרסה קודמת ואינו מוכר נופל לזיהוי אוטומטי', () {
      expect(
        resolveSettingsLanguage(
          'klingon',
          systemLocale: const Locale('he', 'IL'),
        ),
        SettingsLanguage.hebrew,
      );
    });
  });

  group('resolveSettingsText', () {
    const catalog = {
      'חיפוש': 'Search',
      'דף|printing': 'Page',
      'דף|talmud': 'Daf',
      '{count} פעולות זמינות': '{count} actions available',
    };

    test('במצב עברית מוחזר המקור, גם כשיש תרגום', () {
      expect(
        resolveSettingsText(
          'חיפוש',
          language: SettingsLanguage.hebrew,
          catalog: catalog,
        ),
        'חיפוש',
      );
    });

    test('במצב אנגלית מוחזר התרגום', () {
      expect(
        resolveSettingsText(
          'חיפוש',
          language: SettingsLanguage.english,
          catalog: catalog,
        ),
        'Search',
      );
    });

    test('הקשר מפריד בין תרגומים של אותה מחרוזת', () {
      expect(
        resolveSettingsText(
          'דף',
          language: SettingsLanguage.english,
          context: 'printing',
          catalog: catalog,
        ),
        'Page',
      );
      expect(
        resolveSettingsText(
          'דף',
          language: SettingsLanguage.english,
          context: 'talmud',
          catalog: catalog,
        ),
        'Daf',
      );
    });

    test('מפתח חסר נופל למקור העברי במקום להיעלם', () {
      final result = resolveSettingsText(
        'טקסט שאין לו תרגום',
        language: SettingsLanguage.english,
        catalog: catalog,
      );

      // ה-fallback מוקף בבידוד כיווניות; ראה settings_text_bidi_test.
      expect(result, contains('טקסט שאין לו תרגום'));
    });

    test('הקשר שאינו בקטלוג נופל למפתח ללא ההקשר', () {
      expect(
        resolveSettingsText(
          'חיפוש',
          language: SettingsLanguage.english,
          context: 'unknown',
          catalog: catalog,
        ),
        'Search',
      );
    });

    test('placeholders מוחלפים בשתי השפות', () {
      expect(
        resolveSettingsText(
          '{count} פעולות זמינות',
          language: SettingsLanguage.hebrew,
          args: {'count': 3},
          catalog: catalog,
        ),
        '3 פעולות זמינות',
      );
      expect(
        resolveSettingsText(
          '{count} פעולות זמינות',
          language: SettingsLanguage.english,
          args: {'count': 3},
          catalog: catalog,
        ),
        '3 actions available',
      );
    });
  });

  group('ולידציית הקטלוג', () {
    test('מפתח כפול נכשל', () {
      expect(
        () => loadAndValidateCatalog(
          '{"א": "A", "ב": "B", "א": "C"}',
          'test.arb',
        ),
        throwsA(
          isA<SettingsL10nError>().having(
            (e) => e.message,
            'message',
            contains('כפולים'),
          ),
        ),
      );
    });

    test('placeholder חסר בתרגום נכשל', () {
      expect(
        () => loadAndValidateCatalog(
          '{"{count} פריטים": "items"}',
          'test.arb',
        ),
        throwsA(
          isA<SettingsL10nError>().having(
            (e) => e.message,
            'message',
            contains('placeholders'),
          ),
        ),
      );
    });

    test('placeholder עודף בתרגום נכשל', () {
      expect(
        () => loadAndValidateCatalog('{"פריטים": "{count} items"}', 'test.arb'),
        throwsA(isA<SettingsL10nError>()),
      );
    });

    test('מטא-דאטה של ARB אינה נכנסת לקטלוג', () {
      final catalog = loadAndValidateCatalog(
        '{"@@locale": "en", "@חיפוש": {"description": "x"}, "חיפוש": "Search"}',
        'test.arb',
      );
      expect(catalog, {'חיפוש': 'Search'});
    });
  });

  group('סנכרון בין הקוד לקטלוג', () {
    final packageRoot = Directory.current;
    final usages = scanSettingsTextUsages(packageRoot);

    test('הסורק מוצא קריאות בפועל', () {
      expect(usages, isNotEmpty);
    });

    // כל שפה נבדקת בנפרד, כך ששפה שתתווסף בעתיד נכללת מאליה.
    for (final code in kSettingsCatalogs.keys) {
      final catalog = kSettingsCatalogs[code]!;
      final arbPath = '$l10nDirRelativePath/settings_$code.arb';

      test('[$code] לכל מפתח בקוד יש תרגום', () {
        final missing = <String>{};
        for (final usage in usages) {
          if (!catalog.containsKey(usage.key) &&
              !catalog.containsKey(usage.hebrew)) {
            missing.add('${usage.file}: "${usage.key}"');
          }
        }
        expect(
          missing,
          isEmpty,
          reason: 'מפתחות ללא תרגום ב-$arbPath:\n${missing.join('\n')}',
        );
      });

      test('[$code] אין בקטלוג תרגום שאינו בשימוש', () {
        // מפתח נחשב בשימוש אם הוא מופיע כמחרוזת קבועה תחת lib/settings/ —
        // כך גם טקסט שנמסר ל-settingsText דרך משתנה נחשב בשימוש.
        final literals = scanAllStringLiterals(packageRoot);
        final unused = catalog.keys
            .map((key) => key.split('|').first)
            .toSet()
            .where((hebrew) => !literals.contains(hebrew))
            .toList();
        expect(
          unused,
          isEmpty,
          reason: 'תרגומים שאינם בשימוש ב-$arbPath:\n${unused.join('\n')}',
        );
      });
    }

    test('הקובץ המחולל מסונכרן עם קובצי ה-ARB', () {
      expect(
        kSettingsCatalogs,
        loadAllCatalogs(packageRoot),
        reason: 'הרץ: dart run tool/generate_settings_l10n.dart',
      );
    });

    test('הקובץ המחולל פטור מ-dart format', () {
      final generated = File.fromUri(
        packageRoot.uri.resolve(l10nOutputRelativePath),
      ).readAsStringSync();
      expect(
        generated,
        contains('// dart format off'),
        reason:
            'בלי הסימון dart format מגלל את השורות הארוכות, והקובץ מופיע '
            'כשונה מהגיט אחרי כל בנייה',
      );
    });

    test('שפת המקור אינה מקבלת קובץ ARB', () {
      expect(
        findCatalogFiles(packageRoot).containsKey(sourceLanguageCode),
        isFalse,
        reason: 'הטקסט העברי בקוד הוא המפתח ואינו זקוק לקטלוג',
      );
    });
  });

  group('ריבוי קטלוגים', () {
    Directory makeL10nDir(Map<String, String> arbByCode) {
      final dir = Directory.systemTemp.createTempSync('l10n_multi');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory.fromUri(
        dir.uri.resolve('$l10nDirRelativePath/'),
      ).createSync(recursive: true);
      for (final entry in arbByCode.entries) {
        File.fromUri(
          dir.uri.resolve('$l10nDirRelativePath/settings_${entry.key}.arb'),
        ).writeAsStringSync(entry.value);
      }
      return dir;
    }

    test('כל קובץ settings_<code>.arb נאסף לפי קוד השפה שבשמו', () {
      final dir = makeL10nDir({
        'en': '{"חיפוש": "Search"}',
        'fr': '{"חיפוש": "Rechercher"}',
        'pt_BR': '{"חיפוש": "Pesquisar"}',
      });

      expect(
        findCatalogFiles(dir).keys.toSet(),
        {'en', 'fr', 'pt_BR'},
      );
      expect(loadAllCatalogs(dir), {
        'en': {'חיפוש': 'Search'},
        'fr': {'חיפוש': 'Rechercher'},
        'pt_BR': {'חיפוש': 'Pesquisar'},
      });
    });

    test('שפה חדשה נכנסת לקובץ המחולל בלי שינוי קוד', () {
      final dir = makeL10nDir({
        'en': '{"חיפוש": "Search"}',
        'fr': '{"חיפוש": "Rechercher"}',
      });

      final result = generateSettingsL10n(dir);
      expect(result.entriesCount, 2);

      final generated = File.fromUri(
        dir.uri.resolve(l10nOutputRelativePath),
      ).readAsStringSync();
      expect(generated, contains("'en': {"));
      expect(generated, contains("'fr': {"));
      expect(generated, contains("'Rechercher'"));
    });

    test('קטלוג לשפת המקור נדחה — הטקסט בקוד הוא המפתח', () {
      final dir = makeL10nDir({'he': '{"חיפוש": "חיפוש"}'});
      expect(
        () => loadAllCatalogs(dir),
        throwsA(
          isA<SettingsL10nError>().having(
            (e) => e.message,
            'message',
            contains('שפת המקור'),
          ),
        ),
      );
    });

    test('שגיאה בקטלוג אחד מזהה את הקובץ הפוגע', () {
      final dir = makeL10nDir({
        'en': '{"חיפוש": "Search"}',
        'fr': '{"{count} פריטים": "articles"}',
      });
      expect(
        () => loadAllCatalogs(dir),
        throwsA(
          isA<SettingsL10nError>().having(
            (e) => e.message,
            'message',
            allOf(contains('settings_fr.arb'), contains('placeholders')),
          ),
        ),
      );
    });
  });

  group('הסורק', () {
    test('מחבר מחרוזות סמוכות כפי ש-Dart מחבר אותן', () {
      final dir = Directory.systemTemp.createTempSync('l10n_scan');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/'),
      ).createSync(recursive: true);
      File.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/a.dart'),
      ).writeAsStringSync('''
        x(context.settingsText('חלק ראשון '
            'וחלק שני'));
      ''');

      final usages = scanSettingsTextUsages(dir);
      expect(usages.map((u) => u.key), ['חלק ראשון וחלק שני']);
    });

    test('תופס את שני הענפים של ביטוי תנאי', () {
      final dir = Directory.systemTemp.createTempSync('l10n_scan');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/'),
      ).createSync(recursive: true);
      File.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/a.dart'),
      ).writeAsStringSync(
        "x(context.settingsText(flag ? 'כן' : 'לא'));",
      );

      final usages = scanSettingsTextUsages(dir);
      expect(usages.map((u) => u.key), ['כן', 'לא']);
    });

    test('אפוסטרוף בהערה עברית אינו בולע את הקוד שאחריה', () {
      final dir = Directory.systemTemp.createTempSync('l10n_scan');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/'),
      ).createSync(recursive: true);
      File.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/a.dart'),
      ).writeAsStringSync('''
        // ווידג'ט שמוצג בדסקטופ בלבד
        x(context.settingsText('אחרי ההערה'));
      ''');

      expect(scanSettingsTextUsages(dir).map((u) => u.key), ['אחרי ההערה']);
      expect(scanAllStringLiterals(dir), contains('אחרי ההערה'));
    });

    test('הקשר נצמד למפתח ואינו נספר כמפתח בפני עצמו', () {
      final dir = Directory.systemTemp.createTempSync('l10n_scan');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/'),
      ).createSync(recursive: true);
      File.fromUri(
        dir.uri.resolve('$l10nScanRootRelativePath/a.dart'),
      ).writeAsStringSync(
        "x(context.settingsText('דף', context: 'printing'));",
      );

      final usages = scanSettingsTextUsages(dir);
      expect(usages.single.key, 'דף|printing');
      expect(usages.single.hebrew, 'דף');
    });
  });
}

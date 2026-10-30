import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/core/info/info_topic.dart';
import 'package:otzaria/core/info/view/app_info_dialog.dart';
import 'package:otzaria/core/info/view/info_section_fields.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';

void main() {
  AppInfoReport reportOf(
    InfoTopic topic,
    Map<String, Map<String, dynamic>> sections,
  ) => AppInfoReport(
    topic: topic,
    generatedAt: DateTime.parse('2026-08-20T14:32:00.000'),
    sections: sections,
  );

  Future<void> pumpContent(
    WidgetTester tester,
    AppInfoReport report, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AppInfoDialogContent(report: report)),
        ),
      ),
    );
  }

  group('מקטע התוכנה', () {
    testWidgets('מציג גרסה מאוחדת, סוג התקנה וסוג חשבון בעברית', (
      tester,
    ) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.app, {
          'app': {
            'version': '0.3.2',
            'buildNumber': '12',
            'installedAt': '2026-01-05T09:00:00.000',
            'installedAtSource': 'recorded',
            'updatedAt': '2026-08-01T18:20:00.000',
            'installType': 'allUsers',
            'accountType': 'administrator',
            'elevated': false,
          },
        }),
      );

      expect(find.text('מידע על התוכנה'), findsOneWidget);
      expect(find.text('0.3.2+12'), findsOneWidget);
      expect(find.text('05/01/2026 09:00'), findsOneWidget);
      expect(find.text('כל המשתמשים'), findsOneWidget);
      expect(find.text('מנהל'), findsOneWidget);
      expect(find.text('לא'), findsOneWidget);
    });

    testWidgets('תאריך התקנה נגזר מסומן כמוערך', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.app, {
          'app': {
            'installedAt': '2026-01-05T09:00:00.000',
            'installedAtSource': 'derived',
          },
        }),
      );

      expect(find.text('05/01/2026 09:00 (מוערך)'), findsOneWidget);
    });

    testWidgets('שדה חסר אינו מוצג כלל', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.app, {
          'app': {'installType': 'portable'},
        }),
      );

      expect(find.text('גרסה ניידת'), findsOneWidget);
      expect(find.text('סוג חשבון'), findsNothing);
    });

    testWidgets('כשל באיסוף המקטע מוצג כשגיאה', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.app, {
          'app': {'error': 'PackageInfo נכשל'},
        }),
      );

      expect(find.text('שגיאה באיסוף'), findsOneWidget);
      expect(find.text('PackageInfo נכשל'), findsOneWidget);
    });
  });

  group('מקטע הספרייה', () {
    testWidgets('ספירות מוצגות עם מפריד אלפים וגודל DB מעוצב', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.library, {
          'library': {
            'version': '3.1.4',
            'totalBooks': 12345,
            'personalBooks': 7,
            'databaseSizeBytes': 2 * 1024 * 1024,
          },
        }),
      );

      expect(find.text('12,345'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('2.0 MB'), findsOneWidget);
    });

    testWidgets('מסדים אישיים מצורפים מוצגים עם נתיב, ספירה ומצב', (
      tester,
    ) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.library, {
          'library': {
            'totalBooks': 10,
            'attachedLibraryCount': 2,
            'attachedLibraries': [
              {
                'name': 'הספרייה שלי',
                'slug': 'mine',
                'path': r'D:\db\mine.db',
                'status': 'ok',
                'mode': 'link',
                'placement': 'separateRoot',
                'hidden': true,
                'bookCount': 1200,
                'sizeBytes': 3 * 1024 * 1024,
              },
              {
                'name': 'מסד שנותק',
                'slug': 'gone',
                'path': r'E:\db\gone.db',
                'status': 'unreachable',
                'mode': 'copy',
                'placement': 'mergeIntoLibrary',
                'bookCount': 5,
              },
            ],
          },
        }),
      );

      expect(find.text('מסדי ספרים אישיים'), findsOneWidget);
      expect(find.text('הספרייה שלי'), findsOneWidget);
      expect(find.text(r'D:\db\mine.db'), findsOneWidget);
      expect(find.text('1,200 ספרים · \u20663.0 MB\u2069'), findsOneWidget);
      expect(find.text('מוסתר'), findsOneWidget);
      expect(find.text('מסד שנותק'), findsOneWidget);
      expect(find.text('הקובץ לא נגיש'), findsOneWidget);
      expect(find.text('ממוזג לספרייה'), findsOneWidget);
    });

    testWidgets('בלי מסדים מצורפים מוצגת הודעה', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.library, {
          'library': {
            'totalBooks': 10,
            'attachedLibraryCount': 0,
            'attachedLibraries': <Map<String, dynamic>>[],
          },
        }),
      );

      expect(find.text('לא צורפו מסדי ספרים אישיים'), findsOneWidget);
    });
  });

  group('מקטע התיקיות האישיות', () {
    Map<String, Map<String, dynamic>> foldersSection({
      required List<Map<String, dynamic>> folders,
    }) => {
      'folders': {
        'configuredCount': folders.length,
        'existingCount': folders.where((f) => f['exists'] == true).length,
        'totalFiles': folders.fold<int>(
          0,
          (sum, f) => sum + (f['fileCount'] as int? ?? 0),
        ),
        'totalSizeBytes': 1536,
        'folders': folders,
      },
    };

    for (final width in [360.0, 1000.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('קו יחיד בין קבצים ברוחב $width ובמצב $brightness', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final scheme = AppThemeData.createColorScheme(
            AppSeedColors.defaultLight,
            brightness,
          );
          final theme = brightness == Brightness.light
              ? AppThemeData.light(scheme, compactMenuMode: false)
              : AppThemeData.dark(scheme, compactMenuMode: false);
          const names = ['בראשית.txt', 'ויקרא.txt', 'שולחן ערוך.pdf'];
          await pumpContent(
            tester,
            reportOf(
              InfoTopic.folders,
              foldersSection(
                folders: [
                  {
                    'path': r'D:\ספרים שלי',
                    'exists': true,
                    'fileCount': names.length,
                    'files': [
                      for (final name in names) {'name': name},
                    ],
                  },
                ],
              ),
            ),
            theme: theme,
          );
          final context = tester.element(find.byType(AppInfoDialogContent));
          for (var i = 1; i < names.length; i++) {
            final previous = tester.getRect(find.text(names[i - 1]));
            final next = tester.getRect(find.text(names[i]));
            final between = find.byElementPredicate((element) {
              if (element.widget is! Divider) return false;
              final rect = tester.getRect(
                find.byElementPredicate((other) => identical(other, element)),
              );
              return rect.top >= previous.bottom && rect.bottom <= next.top;
            });
            expect(between, findsOneWidget);
            final divider = tester.widget<Divider>(between);
            expect(divider.height, 1);
            expect(divider.color, AppSurfaces.cardRowDivider(context));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('כל תיקייה מוצגת עם נתיב, תקציר ופירוט סיומות', (tester) async {
      await pumpContent(
        tester,
        reportOf(
          InfoTopic.folders,
          foldersSection(
            folders: [
              {
                'path': r'D:\ספרים שלי',
                'exists': true,
                'hidden': false,
                'fileCount': 3,
                'sizeBytes': 1536,
                'filesByType': {'pdf': 1, 'txt': 2},
                'files': [
                  {'name': 'בראשית.txt'},
                  {'name': 'ויקרא.txt'},
                  {'name': 'שולחן ערוך.pdf'},
                ],
              },
            ],
          ),
        ),
      );

      expect(find.text('תיקיות ספרים אישיים'), findsOneWidget);
      expect(find.text(r'D:\ספרים שלי'), findsOneWidget);
      expect(find.text('3 קבצים · \u20661.5 KB\u2069'), findsOneWidget);
      expect(find.text('pdf 1 · txt 2'), findsOneWidget);
      expect(find.text('בראשית.txt'), findsOneWidget);
      expect(find.text('שולחן ערוך.pdf'), findsOneWidget);
    });

    testWidgets('רשימת קבצים ארוכה מקוצרת עם "ועוד"', (tester) async {
      await pumpContent(
        tester,
        reportOf(
          InfoTopic.folders,
          foldersSection(
            folders: [
              {
                'path': r'D:\רבים',
                'exists': true,
                'fileCount': 40,
                'sizeBytes': 0,
                'filesByType': {'txt': 40},
                'files': [
                  for (var i = 0; i < 25; i++) {'name': 'ספר$i.txt'},
                ],
              },
            ],
          ),
        ),
      );

      expect(find.text('ספר0.txt'), findsOneWidget);
      // 10 מוצגים מתוך 40 שנספרו — ההפרש נמדד מול הספירה, לא מול הרשימה.
      expect(find.text('ספר10.txt'), findsNothing);
      expect(find.text('ועוד 30…'), findsOneWidget);
    });

    testWidgets('לחיצה על "ועוד" מרחיבה את הרשימה ו"הצג פחות" מכווצת', (
      tester,
    ) async {
      await pumpContent(
        tester,
        reportOf(
          InfoTopic.folders,
          foldersSection(
            folders: [
              {
                'path': r'D:\רבים',
                'exists': true,
                'fileCount': 40,
                'sizeBytes': 0,
                'filesByType': {'txt': 40},
                'files': [
                  for (var i = 0; i < 25; i++) {'name': 'ספר$i.txt'},
                ],
              },
            ],
          ),
        ),
      );

      await tester.ensureVisible(find.text('ועוד 30…'));
      await tester.tap(find.text('ועוד 30…'));
      await tester.pump();

      // כל 25 הקבצים שברשימה מוצגים; ה-15 האחרים נחתכו ע"י `files=` ולכן
      // "ועוד" שנשאר הוא טקסט בלבד.
      expect(find.text('ספר24.txt'), findsOneWidget);
      expect(find.text('ועוד 15…'), findsOneWidget);

      await tester.ensureVisible(find.text('הצג פחות'));
      await tester.tap(find.text('הצג פחות'));
      await tester.pump();

      expect(find.text('ספר10.txt'), findsNothing);
      expect(find.text('ועוד 30…'), findsOneWidget);
    });

    testWidgets('תיקייה חסרה מסומנת במקום להיראות ריקה', (tester) async {
      await pumpContent(
        tester,
        reportOf(
          InfoTopic.folders,
          foldersSection(
            folders: [
              {'path': r'E:\נותק', 'exists': false, 'fileCount': 0},
            ],
          ),
        ),
      );

      expect(find.text('התיקייה לא נמצאה'), findsOneWidget);
    });

    testWidgets('בלי תיקיות מוגדרות מוצגת הודעה ולא רשימה ריקה', (
      tester,
    ) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.folders, foldersSection(folders: const [])),
      );

      expect(find.text('לא הוגדרו תיקיות ספרים אישיים'), findsOneWidget);
    });
  });

  group('מקטע התוספים', () {
    testWidgets('רשימת מזהי התוספים עם הגרסה המותקנת', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.plugins, {
          'plugins': {
            'webViewVersion': '141.0.3537.85',
            'installedCount': 2,
            'enabledCount': 1,
            'installed': [
              {'id': 'com.a.one', 'version': '1.0.0', 'enabled': true},
              {'id': 'com.b.two', 'version': '2.5.1', 'enabled': false},
            ],
          },
        }),
      );

      expect(find.text('141.0.3537.85'), findsOneWidget);
      expect(find.text('com.a.one'), findsOneWidget);
      expect(find.text('1.0.0'), findsOneWidget);
      expect(find.text('com.b.two'), findsOneWidget);
      expect(find.text('2.5.1 (מושבת)'), findsOneWidget);
    });
  });

  group('מקטע השגיאות', () {
    testWidgets('רשומות אחרונות מוצגות עם זמן והודעה', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.errors, {
          'errors': {
            'totalEntries': 3,
            'recent': [
              {
                'title': 'Flutter error',
                'timestamp': '2026-08-20T10:15:00.000',
                'message': 'RangeError (index)',
              },
            ],
          },
        }),
      );

      expect(find.text('Flutter error'), findsOneWidget);
      expect(find.text('20/08/2026 10:15'), findsOneWidget);
      expect(find.text('RangeError (index)'), findsOneWidget);
    });

    testWidgets('לוג ריק מציג "אין שגיאות"', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.errors, {
          'errors': {'totalEntries': 0, 'recent': const []},
        }),
      );

      expect(find.text('אין שגיאות'), findsOneWidget);
    });
  });

  group('JSON גולמי', () {
    testWidgets('כפתור ההצגה חושף ומסתיר את ה-JSON', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.app, {
          'app': {'version': '0.3.2'},
        }),
      );

      expect(find.textContaining('"topic": "app"'), findsNothing);

      await tester.tap(find.text('הצג JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"topic": "app"'), findsOneWidget);

      await tester.tap(find.text('הסתר JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"topic": "app"'), findsNothing);
    });
  });

  group('דוח מלא', () {
    testWidgets('all מציג את ארבעת המקטעים הקלים', (tester) async {
      await pumpContent(
        tester,
        reportOf(InfoTopic.all, {
          'app': {'version': '0.3.2'},
          'library': {'version': '3.1.4'},
          'plugins': {'installedCount': 0, 'installed': const []},
          'errors': {'totalEntries': 0, 'recent': const []},
        }),
      );

      expect(find.text('מידע על התוכנה'), findsOneWidget);
      expect(find.text('מידע על הספרייה'), findsOneWidget);
      expect(find.text('תיקיות ספרים אישיים'), findsNothing);
      expect(find.text('מידע על התוספים'), findsOneWidget);
      expect(find.text('השגיאות האחרונות'), findsOneWidget);
    });
  });

  group('התאמה לגדלי מסך', () {
    final fullReport = reportOf(InfoTopic.all, {
      'app': {
        'version': '0.3.2',
        'buildNumber': '112',
        'installedAt': '2026-01-05T09:14:00.000',
        'installedAtSource': 'derived',
        'updatedAt': '2026-08-01T18:20:00.000',
        'previousVersion': '0.3.1',
        'installType': 'allUsers',
        'accountType': 'administrator',
        'elevated': false,
        'platform': 'windows',
        'operatingSystem': 'Windows 11 Pro 10.0.26200',
        'dataRootPath': r'C:\Users\User\AppData\Roaming\otzaria',
      },
      'library': {
        'version': '3.1.4',
        'lastUpdatedAt': '2026-08-11T22:05:00.000',
        'totalBooks': 24187,
        'personalBooks': 14,
        'pdfBooks': 1203,
        'databaseSizeBytes': 3221225472,
        'path': r'D:\אוצריא\books',
        'indexPath': r'D:\אוצריא\index',
      },
      'folders': {
        'configuredCount': 1,
        'existingCount': 1,
        'totalFiles': 128,
        'totalSizeBytes': 78643200,
        'folders': [
          {
            'path': r'D:\אוצריא\ספרים אישיים ארוכים במיוחד\תיקייה',
            'exists': true,
            'hidden': false,
            'fileCount': 128,
            'sizeBytes': 78643200,
            'filesByType': {'docx': 8, 'pdf': 20, 'txt': 100},
            'files': [
              {'name': 'שולחן ערוך אורח חיים עם נושאי כלים.docx'},
            ],
          },
        ],
      },
      'plugins': {
        'webViewVersion': '141.0.3537.85',
        'installedCount': 1,
        'enabledCount': 1,
        'installed': [
          {'id': 'com.otzaria.some.long.plugin.id', 'version': '1.4.0'},
        ],
      },
      'errors': {
        'totalEntries': 7,
        'recent': [
          {
            'title': 'Flutter error',
            'timestamp': '2026-08-19T21:04:00.000',
            'message': 'RangeError (index): Invalid value: Not in range 0..12',
          },
        ],
      },
    });

    for (final size in const [
      Size(360, 640), // טלפון צר
      Size(800, 600), // חלון דסקטופ מינימלי
      Size(1600, 1000), // דסקטופ רחב
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} בלי חריגה', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showAppInfoDialog(context, fullReport),
                    child: const Text('פתח'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('פתח'));
        await tester.pumpAndSettle();

        expect(find.byType(AppInfoDialogContent), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('InfoValueFormat', () {
    test('count מוסיף מפריד אלפים', () {
      expect(InfoValueFormat.count(0), '0');
      expect(InfoValueFormat.count(999), '999');
      expect(InfoValueFormat.count(1000), '1,000');
      expect(InfoValueFormat.count(1234567), '1,234,567');
      expect(InfoValueFormat.count(null), InfoValueFormat.dash);
    });

    test('bytes עולה יחידות', () {
      expect(InfoValueFormat.bytes(512), '512 B');
      expect(InfoValueFormat.bytes(1536), '1.5 KB');
      expect(InfoValueFormat.bytes(3 * 1024 * 1024 * 1024), '3.0 GB');
      expect(InfoValueFormat.bytes('x'), InfoValueFormat.dash);
    });

    test('yesNo וטקסט ריק', () {
      expect(InfoValueFormat.yesNo(true), 'כן');
      expect(InfoValueFormat.yesNo(false), 'לא');
      expect(InfoValueFormat.yesNo(null), InfoValueFormat.dash);
      expect(InfoValueFormat.text('  '), InfoValueFormat.dash);
    });
  });
}

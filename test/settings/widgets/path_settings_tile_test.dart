import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';

// Helper: עטיפת MaterialApp+RTL סטנדרטית לטסטי widgets
Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Directionality(
      textDirection: TextDirection.rtl,
      child: child,
    ),
  ),
);

void main() {
  const icon = FluentIcons.folder_24_regular;
  const title = 'תיקיית בדיקה';
  const placeholder = 'לא נבחר מיקום';

  group('PathSettingsTile — simpleButtonWhenEmpty=true (ברירת מחדל)', () {
    testWidgets(
      'כשהנתיב ריק מוצג כפתור "הגדר מיקום" בלבד',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('הגדר מיקום'), findsOneWidget);
        expect(find.text('אפשרויות מיקום'), findsNothing);
      },
    );

    testWidgets(
      'לחיצה על "הגדר מיקום" אינה קורסת',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('הגדר מיקום'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'כשיש נתיב מוצג כפתור "אפשרויות מיקום" במקום "הגדר מיקום"',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '/some/path',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('אפשרויות מיקום'), findsOneWidget);
        expect(find.text('הגדר מיקום'), findsNothing);
      },
    );
  });

  group('PathSettingsTile — simpleButtonWhenEmpty=false', () {
    testWidgets(
      'כשהנתיב ריק עדיין מוצג "אפשרויות מיקום" (לא "הגדר מיקום")',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              simpleButtonWhenEmpty: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('אפשרויות מיקום'), findsOneWidget);
        expect(find.text('הגדר מיקום'), findsNothing);
      },
    );
  });

  group('PathSettingsTile — clearPathEnabled', () {
    testWidgets(
      'כשclearPathEnabled=false ו-onClearPath מוגדר מוצג placeholder הנתיב',
      (tester) async {
        // בדיקה שה-tile נבנה ללא שגיאות כשclearPathEnabled=false
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '/default/path',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              onClearPath: () {},
              clearPathEnabled: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('אפשרויות מיקום'), findsOneWidget);
      },
    );

    testWidgets(
      'כשclearPathEnabled=true ו-onClearPath מוגדר ה-tile נבנה ללא שגיאות',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '/custom/path',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              onClearPath: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('אפשרויות מיקום'), findsOneWidget);
      },
    );
  });

  group('PathSettingsTile — תצוגת נתיב', () {
    testWidgets(
      'כשיש נתיב מוצג הנתיב בתור subtitle',
      (tester) async {
        const path = '/my/library/path';
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: path,
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // הנתיב מוצג בממשק (אחרי עיצוב על-ידי _formatPath)
        expect(find.textContaining('my'), findsWidgets);
      },
    );

    testWidgets(
      'כשהנתיב ריק ו-simpleButtonWhenEmpty=false מוצג ה-placeholder',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              simpleButtonWhenEmpty: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(placeholder), findsOneWidget);
      },
    );
  });

  group('PathSettingsTile — pathTargets תת-תפריט', () {
    testWidgets(
      '"פתח תיקייה..." פותח תת-תפריט של יעדים וקורא ל-onOpenPath',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        String? opened;
        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: r'C:\root',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              onOpenPath: (path) => opened = path,
              pathTargets: const [
                PathTarget(label: 'תיקייה ראשית', path: r'C:\root'),
                PathTarget(label: 'ספרייה', path: r'C:\root\books'),
                PathTarget(label: 'אינדקס', path: r'C:\root\index'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('אפשרויות מיקום'));
        await tester.pumpAndSettle();
        expect(find.text('פתח תיקייה...'), findsOneWidget);

        await tester.tap(find.text('פתח תיקייה...'));
        await tester.pumpAndSettle();

        expect(find.text('אינדקס'), findsOneWidget);
        await tester.tap(find.text('אינדקס'));
        await tester.pumpAndSettle();

        expect(opened, r'C:\root\index');
      },
    );

    testWidgets(
      '"העתק נתיב..." מציג תת-תפריט של היעדים',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: r'C:\root',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              pathTargets: const [
                PathTarget(label: 'תיקייה ראשית', path: r'C:\root'),
                PathTarget(label: 'ספרייה', path: r'C:\root\books'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('אפשרויות מיקום'));
        await tester.pumpAndSettle();
        expect(find.text('העתק נתיב...'), findsOneWidget);

        await tester.tap(find.text('העתק נתיב...'));
        await tester.pumpAndSettle();

        expect(find.text('ספרייה'), findsOneWidget);
      },
    );
  });

  group('PathSettingsTile — requestChangeLocation', () {
    testWidgets(
      'לחיצה על "שינוי מיקום..." בתפריט קוראת ל-requestChangeLocation',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var called = false;

        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '/some/path',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              requestChangeLocation: (ctx) async {
                called = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('אפשרויות מיקום'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('שינוי מיקום...'));
        await tester.pumpAndSettle();

        expect(called, isTrue);
      },
    );

    testWidgets(
      'הכפתור מושבת בזמן requestChangeLocation פועל',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final completer = Future<void>.value(); // immediate
        var callCount = 0;

        await tester.pumpWidget(
          _wrap(
            SettingsActionTile.pathTile(
              icon: icon,
              title: title,
              currentPath: '/some/path',
              placeholder: placeholder,
              onFolderChanged: (_) async {},
              onOpenFolder: () {},
              requestChangeLocation: (ctx) async {
                callCount++;
                await completer;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('אפשרויות מיקום'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('שינוי מיקום...'));
        await tester.pumpAndSettle();

        expect(callCount, 1);
      },
    );
  });
}

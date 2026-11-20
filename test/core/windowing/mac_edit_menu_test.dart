import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/mac_menu_bar.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// תפריט "עריכה" של מק (הכרעת בעל הפרויקט 18.11, סעיף 65): בלעדיו שורת התפריט
/// של המערכת לא מכילה גזור/העתק/הדבק/בחר הכל, ולכן גם לא אמצעי העריכה של macOS.
PlatformMenu _menu([SettingsLanguage language = SettingsLanguage.hebrew]) =>
    buildMacEditMenu(language: language);

Iterable<PlatformMenuItem> _items(Iterable<PlatformMenuItem> menus) sync* {
  for (final menu in menus) {
    yield menu;
    if (menu is PlatformMenu) yield* _items(menu.menus);
    if (menu is PlatformMenuItemGroup) yield* _items(menu.members);
  }
}

PlatformMenuItem _item(String label) => _items(
  _menu().menus,
).singleWhere((item) => item.label == label && item.onSelected != null);

void main() {
  group('מבנה התפריט', () {
    test('כותרת "עריכה" ובה חמש הפעולות, בשלוש קבוצות', () {
      final menu = _menu();
      expect(menu.label, 'עריכה');
      expect(
        [
          for (final group in menu.menus.whereType<PlatformMenuItemGroup>())
            [for (final member in group.members) member.label],
        ],
        [
          ['בטל', 'בצע שוב'],
          ['גזור', 'העתק', 'הדבק'],
          ['בחר הכל'],
        ],
      );
    });

    test('הפריטים לא מצהירים על מקש: Flutter מטפל במקשים, כמו עד היום', () {
      // הצהרה על Cmd+C בתפריט הייתה תופסת את המקש לפני תצוגת ה-WebView של
      // תוספים, שאין לה Action של Flutter שיטפל בו.
      for (final item in _items(_menu().menus)) {
        if (item.onSelected != null) {
          expect(item.shortcut, isNull, reason: item.label);
        }
      }
    });

    test('באנגלית התפריט מתורגם לפי הקטלוג (ובעברית הוא כפי שהוא)', () {
      final english = _menu(SettingsLanguage.english);
      expect(english.menus, isNotEmpty);
      expect(
        [
          for (final item in _items(english.menus))
            if (item.onSelected != null) item.label,
        ],
        containsAll(['Undo', 'Cut', 'Copy', 'Paste', 'Select All']),
      );
    });
  });

  group('הפעולה מגיעה לרכיב שבפוקוס', () {
    late TextEditingController controller;
    String? clipboard;

    setUp(() {
      controller = TextEditingController(text: 'שלום עולם');
      clipboard = null;
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            if (call.method == 'Clipboard.getData') {
              return <String, Object?>{'text': clipboard};
            }
            if (call.method == 'Clipboard.hasStrings') {
              return <String, Object?>{'value': clipboard?.isNotEmpty ?? false};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      controller.dispose();
    });

    Future<void> pumpField(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
    }

    testWidgets('בחר הכל, העתק, גזור, הדבק, בטל ובצע שוב בשדה טקסט', (
      tester,
    ) async {
      await pumpField(tester);

      _item('בחר הכל').onSelected!();
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );

      _item('העתק').onSelected!();
      await tester.pump();
      expect(clipboard, 'שלום עולם');
      expect(controller.text, 'שלום עולם');

      // היסטוריית הביטול מקבצת שינויים קרובים: ההפסקה הופכת כל פעולה לצעד נפרד.
      _item('גזור').onSelected!();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.text, isEmpty);

      _item('הדבק').onSelected!();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.text, 'שלום עולם');

      _item('בטל').onSelected!();
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);

      _item('בצע שוב').onSelected!();
      await tester.pumpAndSettle();
      expect(controller.text, 'שלום עולם');
    });

    testWidgets('בלי פוקוס אין חריגה ואין שינוי', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );
      for (final label in [
        'בטל',
        'בצע שוב',
        'גזור',
        'העתק',
        'הדבק',
        'בחר הכל',
      ]) {
        expect(_item(label).onSelected!, returnsNormally, reason: label);
      }
      expect(controller.text, 'שלום עולם');
      expect(clipboard, isNull);
    });

    testWidgets('אזור בחירה (SelectionArea) מקבל בחר הכל והעתק', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SelectionArea(child: Text('טקסט נבחר'))),
        ),
      );
      await tester.tapAt(tester.getCenter(find.text('טקסט נבחר')));
      await tester.pump();
      _item('בחר הכל').onSelected!();
      await tester.pump();
      _item('העתק').onSelected!();
      await tester.pump();
      expect(clipboard, 'טקסט נבחר');
    });
  });
}

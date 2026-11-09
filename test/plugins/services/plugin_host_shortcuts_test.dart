import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_host_shortcuts.dart';

void main() {
  tearDown(() => PluginHostShortcuts.isMacForTesting = null);

  PluginHostShortcut byId(List<PluginHostShortcut> list, String id) =>
      list.singleWhere((s) => s.id == id);

  group('PluginHostShortcuts.build', () {
    test('משתמש בערך שהמשתמש הגדיר ולא בברירת המחדל', () {
      PluginHostShortcuts.isMacForTesting = false;
      final list = PluginHostShortcuts.build({
        'key-shortcut-open-library-browser': 'ctrl+shift+q',
      });
      final library = byId(list, 'key-shortcut-open-library-browser');
      expect(library.codes, ['KeyQ']);
      expect(library.ctrl, isTrue);
      expect(library.shift, isTrue);
      expect(library.meta, isFalse);
      // מפתח שלא הוגדר נופל לברירת המחדל (ctrl+o).
      expect(byId(list, 'key-shortcut-open-find-ref').codes, ['KeyO']);
    });

    test('בית הספרייה מועבר לתוסף רק כשהוגדר לו קיצור', () {
      PluginHostShortcuts.isMacForTesting = false;
      const key = 'key-shortcut-open-library-home';
      expect(
        PluginHostShortcuts.build(const {}).map((s) => s.id),
        isNot(contains(key)),
      );
      final home = byId(
        PluginHostShortcuts.build({key: 'ctrl+shift+h'}),
        key,
      );
      expect(home.codes, ['KeyH']);
      expect(home.ctrl, isTrue);
      expect(home.shift, isTrue);
    });

    test('קיצורי עריכה של התוכנה אינם מועברים לתוסף', () {
      final ids = PluginHostShortcuts.build(const {}).map((s) => s.id);
      expect(ids, isNot(contains('key-shortcut-print')));
      expect(ids, isNot(contains('key-shortcut-add-note')));
      expect(ids, isNot(contains('key-shortcut-add-bookmark')));
      expect(ids, isNot(contains('key-shortcut-shamor-zachor-cycle-filter')));
    });

    test('קיצור ריק או לא-מוכר מושמט', () {
      final list = PluginHostShortcuts.build({
        'key-shortcut-open-history': '',
        'key-shortcut-open-more': 'ctrl+shift+כ',
      });
      final ids = list.map((s) => s.id);
      expect(ids, isNot(contains('key-shortcut-open-history')));
      expect(ids, isNot(contains('key-shortcut-open-more')));
    });

    test('ספרה תואמת גם לספרון; comma ו-f11 ממופים לקוד הדפדפן', () {
      PluginHostShortcuts.isMacForTesting = false;
      final list = PluginHostShortcuts.build({
        'key-shortcut-open-history': 'ctrl+3',
        'key-shortcut-open-settings': 'ctrl+comma',
      });
      expect(byId(list, 'key-shortcut-open-history').codes, [
        'Digit3',
        'Numpad3',
      ]);
      expect(byId(list, 'key-shortcut-open-settings').codes, ['Comma']);
      final f11 = byId(list, 'fixed:f11');
      expect(f11.codes, ['F11']);
      expect(f11.ctrl, isFalse);
    });

    test('ב-Mac ה-token ctrl נהיה meta, אבל Ctrl+Tab נשאר Ctrl פיזי', () {
      PluginHostShortcuts.isMacForTesting = true;
      final list = PluginHostShortcuts.build({
        'key-shortcut-close-tab': 'ctrl+w',
      });
      final close = byId(list, 'key-shortcut-close-tab');
      expect(close.meta, isTrue);
      expect(close.ctrl, isFalse);
      final ctrlTab = byId(list, 'fixed:ctrl+tab');
      expect(ctrlTab.ctrl, isTrue);
      expect(ctrlTab.meta, isFalse);
      expect(ctrlTab.codes, ['Tab']);
    });
  });

  group('PluginHostShortcuts.dispatch', () {
    testWidgets('האירוע הסינתטי מגיע ל-late handler עם ה-modifiers לחוצים', (
      tester,
    ) async {
      // כמו באפליקציה: תמיד יש צומת פוקוס ראשי, אחרת FocusManager מתעלם.
      await tester.pumpWidget(const Focus(autofocus: true, child: SizedBox()));
      await tester.pump();
      final seen = <KeyEvent>[];
      var ctrlDuringKey = false;
      var shiftDuringKey = false;
      KeyEventResult handler(KeyEvent event) {
        if (event is KeyDownEvent &&
            event.physicalKey == PhysicalKeyboardKey.keyW) {
          seen.add(event);
          ctrlDuringKey = HardwareKeyboard.instance.isControlPressed;
          shiftDuringKey = HardwareKeyboard.instance.isShiftPressed;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      FocusManager.instance.addLateKeyEventHandler(handler);
      addTearDown(
        () => FocusManager.instance.removeLateKeyEventHandler(handler),
      );

      const shortcut = PluginHostShortcut(
        id: 'key-shortcut-close-all-tabs',
        mainKey: 'w',
        codes: ['KeyW'],
        ctrl: true,
        shift: true,
        alt: false,
        meta: false,
      );
      expect(PluginHostShortcuts.dispatch(shortcut), isTrue);

      expect(seen, hasLength(1));
      expect(ctrlDuringKey, isTrue);
      expect(shiftDuringKey, isTrue);
      // המצב נקי — אף מקש לא נשאר "לחוץ".
      expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
    });

    testWidgets(
      'מקש שנשאר "לחוץ" (שוחרר בתוך ה-WebView) משתחרר והקיצור משוגר (issue #1349)',
      (tester) async {
        await tester.pumpWidget(
          const Focus(autofocus: true, child: SizedBox()),
        );
        await tester.pump();
        // Ctrl+Tab בספר: Tab נלחץ ב-Flutter, והשחרור שלו הלך לתוסף שקיבל פוקוס.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        var tabDowns = 0;
        KeyEventResult handler(KeyEvent event) {
          if (event is KeyDownEvent &&
              event.physicalKey == PhysicalKeyboardKey.tab &&
              HardwareKeyboard.instance.isControlPressed) {
            tabDowns++;
          }
          return KeyEventResult.ignored;
        }

        FocusManager.instance.addLateKeyEventHandler(handler);
        addTearDown(
          () => FocusManager.instance.removeLateKeyEventHandler(handler),
        );

        const shortcut = PluginHostShortcut(
          id: 'fixed:ctrl+tab',
          mainKey: 'tab',
          codes: ['Tab'],
          ctrl: true,
          shift: false,
          alt: false,
          meta: false,
        );
        expect(PluginHostShortcuts.dispatch(shortcut), isTrue);
        expect(PluginHostShortcuts.dispatch(shortcut), isTrue);

        expect(tabDowns, 2);
        expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
      },
    );
  });
}

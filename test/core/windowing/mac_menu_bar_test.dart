import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/mac_menu_bar.dart';

class _SettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _SettingsBloc()
    : super(SettingsState.initial().copyWith(settingsLanguageCode: 'he'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _NavigationBloc()
    : super(const NavigationState(currentScreen: Screen.settings)) {
    on<NavigationEvent>((event, _) => events.add(event));
  }
  final events = <NavigationEvent>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Iterable<PlatformMenuItem> _items(Iterable<PlatformMenuItem> menus) sync* {
  for (final menu in menus) {
    yield menu;
    if (menu is PlatformMenu) yield* _items(menu.menus);
    if (menu is PlatformMenuItemGroup) yield* _items(menu.members);
  }
}

void main() {
  for (final extraRoute in [false, true]) {
    testWidgets(
      'תפריט מק מכבד התקנה חסומה, שכבה נוספת: $extraRoute',
      (
        tester,
      ) async {
        final settings = _SettingsBloc();
        final navigation = _NavigationBloc();
        final dismissible = ValueNotifier(false);
        final focus = FocusRepository()..resetForTesting();
        focus.librarySearchController.text = 'חיפוש';
        focus.librarySearchController.selection = const TextSelection.collapsed(
          offset: 2,
        );
        final tools = ToolsLauncherController.instance;
        final initialTools = tools.openCount;
        addTearDown(() async {
          await settings.close();
          await navigation.close();
          dismissible.dispose();
          focus.resetForTesting();
        });
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<NavigationBloc>.value(value: navigation),
            ],
            child: Provider<FocusRepository>.value(
              value: focus,
              child: MacMenuBar(
                child: MaterialApp(
                  navigatorKey: navigatorKey,
                  home: const Scaffold(body: Text('בית')),
                ),
              ),
            ),
          ),
        );
        void selectMenu(String label) =>
            _items(
                  tester
                      .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
                      .menus,
                )
                .singleWhere(
                  (item) => item.label == label && item.onSelected != null,
                )
                .onSelected!();
        showDialog<void>(
          context: tester.element(find.text('בית')),
          builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: dismissible,
            builder: (_, canDismiss, _) => AppDialogFrame(
              title: 'התקנה פעילה',
              icon: Icons.extension,
              closeEnabled: canDismiss,
              child: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (extraRoute) {
          showDialog<void>(
            context: tester.element(find.byType(AppDialogFrame)),
            builder: (_) => const AlertDialog(title: Text('שכבה נוספת')),
          );
          await tester.pumpAndSettle();
        }
        for (final label in ['ספרייה', 'כלים', 'סימניות', 'הגדרות…']) {
          selectMenu(label);
          await tester.pumpAndSettle();
          expect(find.text('התקנה פעילה'), findsOneWidget);
          expect(find.text('שכבה נוספת'), findsNothing);
          expect(navigation.events, isEmpty);
          expect(tools.openCount, initialTools);
          expect(focus.librarySearchController.selection.baseOffset, 2);
        }
        dismissible.value = true;
        await tester.pump();
        selectMenu('ספרייה');
        await tester.pumpAndSettle();
        expect(find.text('התקנה פעילה'), findsNothing);
        expect(navigation.events, [const NavigateToScreen(Screen.library)]);
        expect(focus.librarySearchController.selection.baseOffset, 0);
      },
      skip: !Platform.isMacOS,
      variant: TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  group('menuShortcutActivator', () {
    test('ctrl בהגדרות הוא Command בתפריט של מק', () {
      final activator = menuShortcutActivator('ctrl+l');
      expect(activator, isNotNull);
      expect(activator!.trigger, LogicalKeyboardKey.keyL);
      expect(activator.meta, isTrue);
      expect(activator.shift, isFalse);
      expect(activator.alt, isFalse);
    });

    test('מקש בעל שם מהמפה המרכזית שאינו סימן תלוי־פריסה', () {
      final activator = menuShortcutActivator('ctrl+f11');
      expect(activator!.trigger, LogicalKeyboardKey.f11);
      expect(activator.meta, isTrue);
    });

    test('סימן תלוי־פריסה נשאר לטיפול Flutter לפי מיקום פיזי', () {
      expect(menuShortcutActivator('ctrl+comma'), isNull);
      expect(menuShortcutActivator('ctrl+period'), isNull);
    });

    test('צירוף עם shift', () {
      final activator = menuShortcutActivator('ctrl+shift+f');
      expect(activator!.trigger, LogicalKeyboardKey.keyF);
      expect(activator.meta, isTrue);
      expect(activator.shift, isTrue);
    });

    test('meta נחשב כמו ctrl', () {
      expect(menuShortcutActivator('meta+b')!.meta, isTrue);
    });

    test('alt נשמר', () {
      expect(menuShortcutActivator('alt+b')!.alt, isTrue);
    });

    test('ריק או null מחזיר null', () {
      expect(menuShortcutActivator(null), isNull);
      expect(menuShortcutActivator(''), isNull);
    });

    test('מקש שאינו ניתן לייצוג מחזיר null במקום קיצור שגוי', () {
      expect(menuShortcutActivator('ctrl+שין'), isNull);
      expect(menuShortcutActivator('ctrl'), isNull);
    });

    test('כל ברירות המחדל שאינן סימנים תלויי־פריסה ניתנות להצהרה בתפריט', () {
      // הצהרה שגויה בתפריט הייתה חוטפת את המקש מ-KeyboardShortcuts.
      for (final shortcut in const [
        'ctrl+l',
        'ctrl+f',
        'ctrl+o',
        'ctrl+w',
        'ctrl+shift+w',
        'ctrl+shift+t',
        'ctrl+shift+a',
        'ctrl+r',
        'ctrl+shift+f',
        'ctrl+m',
        'ctrl+shift+b',
        'ctrl+y',
        'ctrl+b',
        'ctrl+k',
      ]) {
        expect(
          menuShortcutActivator(shortcut),
          isNotNull,
          reason: 'הקיצור $shortcut צריך להיות ניתן להצהרה בתפריט',
        );
      }
    });
  });
}

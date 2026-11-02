import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/shortcuts/key_map.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:flutter/material.dart' show showDialog;

/// תפריט המערכת של מק — ה-menu bar שבראש המסך.
///
/// בלעדיו נשאר תפריט ברירת המחדל של תבנית Flutter: פריטי עריכה שאינם עושים
/// דבר כאן, ו"העדפות…" מת. מחוץ למק מחזיר את [child] כפי שהוא.
class MacMenuBar extends StatelessWidget {
  const MacMenuBar({super.key, required this.child});

  final Widget child;

  static bool get _isSupported => !kIsWeb && Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) return child;
    // הקיצורים נקראים מההגדרות ולא מקובעים: מקש שמוצהר בתפריט נתפס בידי
    // macOS לפני Flutter, וקיצור מיושן כאן היה חוטף את החדש.
    // התפריט יושב מעל SettingsTextScope של האפליקציה, ולכן השפה נקראת מההגדרות.
    return BlocSelector<
      SettingsBloc,
      SettingsState,
      (Map<String, String>, String)
    >(
      selector: (state) => (state.shortcuts, state.settingsLanguageCode),
      builder: (context, selected) => PlatformMenuBar(
        menus: _menus(
          selected.$1,
          resolveSettingsLanguage(selected.$2),
        ),
        child: child,
      ),
    );
  }

  List<PlatformMenuItem> _menus(
    Map<String, String> shortcuts,
    SettingsLanguage language,
  ) {
    String t(String hebrew) => resolveSettingsText(hebrew, language: language);
    MenuSerializableShortcut? accel(String key) =>
        _toActivator(shortcuts[key] ?? ShortcutValidator.defaultShortcuts[key]);

    return <PlatformMenuItem>[
      // התווית מתעלמים ממנה: macOS מציגה תמיד את שם האפליקציה בתפריט הראשון.
      PlatformMenu(
        label: 'אוצריא',
        menus: <PlatformMenuItem>[
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformMenuItem(
                label: t('הגדרות…'),
                shortcut: accel('key-shortcut-open-settings'),
                onSelected: _openSettings,
              ),
            ],
          ),
          const PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.servicesSubmenu,
              ),
            ],
          ),
          const PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hide,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hideOtherApplications,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.showAllApplications,
              ),
            ],
          ),
          const PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: t('מעבר'),
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: resolveSettingsText(
              'ספרייה',
              language: language,
              context: 'titleBar',
            ),
            shortcut: accel('key-shortcut-open-library-browser'),
            onSelected: _openLibrary,
          ),
          PlatformMenuItem(
            label: t('עיון'),
            shortcut: accel('key-shortcut-open-reading-screen'),
            onSelected: () => _navigate(Screen.reading),
          ),
          PlatformMenuItem(
            label: t('חיפוש'),
            shortcut: accel('key-shortcut-open-new-search'),
            onSelected: () => _navigate(Screen.search),
          ),
          PlatformMenuItem(
            label: t('כלים'),
            shortcut: accel('key-shortcut-open-more'),
            onSelected: _openTools,
          ),
        ],
      ),
      PlatformMenu(
        label: t('סימניות'),
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: t('סימניות'),
            shortcut: accel('key-shortcut-open-bookmarks'),
            onSelected: () => _showDialog(const BookmarksDialog()),
          ),
          PlatformMenuItem(
            label: t('היסטוריה'),
            shortcut: accel('key-shortcut-open-history'),
            onSelected: () => _showDialog(const HistoryDialog()),
          ),
        ],
      ),
      PlatformMenu(
        label: t('חלון'),
        menus: const <PlatformMenuItem>[
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              // האפליקציה מאזינה ל-onWindowEnterFullScreen/Leave, ולכן מסך
              // מלא מהתפריט נשאר מסונכרן עם מצב הסרגל המותאם.
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.toggleFullScreen,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
              ),
            ],
          ),
        ],
      ),
    ];
  }

  static bool _navigate(Screen screen) {
    final context = navigatorKey.currentContext;
    if (context == null || !_closeOverlayRoutes(context)) return false;
    context.read<NavigationBloc>().add(NavigateToScreen(screen));
    return true;
  }

  static void _openSettings() => _navigate(Screen.settings);

  static void _openLibrary() {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    if (!_navigate(Screen.library)) return;
    context.read<FocusRepository>().requestLibrarySearchFocus(selectAll: true);
  }

  static void _openTools() {
    final context = navigatorKey.currentContext;
    if (context == null || !_closeOverlayRoutes(context)) return;
    ToolsLauncherController.instance.open();
  }

  static void _showDialog(Widget dialog) {
    final context = navigatorKey.currentContext;
    if (context == null || !_closeOverlayRoutes(context)) return;
    showDialog(context: context, builder: (_) => dialog);
  }

  /// דיאלוג או תפריט פתוח נסגר לפני המעבר — בדיוק כמו במסלול הקיצורים.
  static bool _closeOverlayRoutes(BuildContext context) {
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    var blocked = false;
    if (navigator?.canPop() ?? false) {
      navigator!.popUntil((route) {
        blocked =
            !route.isFirst &&
            route.popDisposition == RoutePopDisposition.doNotPop;
        return route.isFirst || blocked;
      });
    }
    return !blocked;
  }
}

/// ממיר מחרוזת קיצור בפורמט ההגדרות ל-activator שניתן להצהיר עליו בתפריט.
///
/// מחזיר `null` לקיצור שאינו ניתן לייצוג, או לסימן תלוי־פריסה. במקרה כזה
/// הפריט מוצג בלי מקש, והקיצור מטופל ב-`KeyboardShortcuts` לפי מיקומו הפיזי.
@visibleForTesting
SingleActivator? menuShortcutActivator(String? shortcut) =>
    _toActivator(shortcut);

SingleActivator? _toActivator(String? shortcut) {
  if (shortcut == null || shortcut.isEmpty) return null;
  var meta = false;
  var shift = false;
  var alt = false;
  LogicalKeyboardKey? key;
  for (final part in shortcut.toLowerCase().split('+')) {
    switch (part) {
      // במק `ctrl` שבהגדרות הוא Command — כך גם ShortcutHelper מפרש אותו.
      case 'ctrl' || 'control' || 'meta':
        meta = true;
      case 'shift':
        shift = true;
      case 'alt':
        alt = true;
      case '':
        continue;
      default:
        if (KeyMap.isLayoutSensitiveSymbol(part)) return null;
        final mapped = KeyMap.nameToKey[part];
        if (mapped != null) {
          key = mapped;
        } else if (part.length == 1 &&
            part.codeUnitAt(0) >= 0x61 &&
            part.codeUnitAt(0) <= 0x7a) {
          // מזהי המקשים הלוגיים של a–z הם קודי ה-Unicode שלהם.
          key = LogicalKeyboardKey(part.codeUnitAt(0));
        } else {
          return null;
        }
    }
  }
  if (key == null) return null;
  return SingleActivator(key, meta: meta, shift: shift, alt: alt);
}

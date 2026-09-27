import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

class MatchedControl {
  final int hwnd;

  const MatchedControl({required this.hwnd});
}

class DiscoveredDialog {
  final int hwnd;
  final int container;
  final Map<String, MatchedControl> controls;

  const DiscoveredDialog({
    required this.hwnd,
    required this.container,
    required this.controls,
  });

  int? handle(String role) => controls[role]?.hwnd;

  bool get alive =>
      ResponsaWin32.isWindow(hwnd) &&
      controls.values.every((c) => ResponsaWin32.isWindow(c.hwnd));
}

/// גילוי **מבני** של חלונות ופקדים.
///
/// הדפוס: מאתרים את המכל שילדיו מכילים את **כל** התפקידים הנדרשים יחד
/// (Edit + Button + ListBox), ולא כל פקד בנפרד. כך הדיאלוג נמצא גם
/// כשהמזהים שונים ממה שהכרנו.
class ResponsaDiscovery {
  ResponsaDiscovery._();

  static int? findMainWindow(int pid, ResponsaVersionProfile profile) {
    for (final hwnd in ResponsaWin32.topWindows(pid)) {
      if (ResponsaWin32.className(hwnd) == profile.mainWindowClass) return hwnd;
    }
    return null;
  }

  @visibleForTesting
  static bool titleMatches(String title, DialogHints hints) {
    if (hints.titleEquals.isNotEmpty) {
      return hints.titleEquals.contains(title.trim());
    }
    if (hints.titleContains.isNotEmpty) {
      return hints.titleContains.any(title.contains);
    }
    return true;
  }

  /// חלונות העל שעונים למחלקה ולכותרת, **נראים תחילה**.
  ///
  /// סדר הנראות אינו קוסמטי: דיאלוג עיון ישן יכול להישאר פתוח וחונה
  /// מחוץ למסך. הוא תואם למחלקה ולכותרת בדיוק כמו החי, אבל אינו מגיב —
  /// וכל עוד הוא נבחר, כל הפניה מחזירה 0 תוצאות בלי סיבה נראית לעין.
  ///
  /// [visibleOnly] נבדק **לפני** קריאת הכותרת: קריאת טקסט היא הודעה
  /// סינכרונית, וחלון חונה עולה את מלוא תקרת הזמן.
  static List<int> candidateDialogs(
    int pid,
    DialogHints hints, {
    bool visibleOnly = false,
  }) {
    final found = <int>[];
    for (final hwnd in ResponsaWin32.topWindows(pid)) {
      if (ResponsaWin32.className(hwnd) != hints.windowClass) continue;
      if (visibleOnly && !ResponsaWin32.isVisible(hwnd)) continue;
      if (hints.topLevel && !ResponsaWin32.isTopLevel(hwnd)) continue;
      if (!titleMatches(ResponsaWin32.windowText(hwnd), hints)) continue;
      found.add(hwnd);
    }
    found.sort((a, b) {
      final va = ResponsaWin32.isVisible(a) ? 0 : 1;
      final vb = ResponsaWin32.isVisible(b) ? 0 : 1;
      return va.compareTo(vb);
    });
    return found;
  }

  static MatchedControl? _matchControl(
    List<int> candidates,
    ControlHints hints,
  ) {
    final byClass = candidates
        .where((h) => hints.classNames.contains(ResponsaWin32.className(h)))
        .toList();
    if (byClass.isEmpty) return null;

    if (hints.controlIds.isNotEmpty) {
      for (final hwnd in byClass) {
        final id = ResponsaWin32.controlId(hwnd);
        if (hints.controlIds.contains(id)) {
          return MatchedControl(hwnd: hwnd);
        }
      }
    }

    if (hints.textContains.isNotEmpty) {
      for (final hwnd in byClass) {
        // '&' הוא סמן מקש-קיצור ואינו חלק מהתווית.
        final text = ResponsaWin32.windowText(hwnd).replaceAll('&', '');
        if (hints.textContains.any(text.contains)) {
          return MatchedControl(hwnd: hwnd);
        }
      }
    }

    if (byClass.length == 1) {
      return MatchedControl(hwnd: byClass.single);
    }
    return null;
  }

  static Map<String, MatchedControl>? _matchContainer(
    int container,
    DialogHints hints,
  ) {
    final candidates = ResponsaWin32.children(container);
    if (candidates.isEmpty) return null;

    final matched = <String, MatchedControl>{};
    for (final control in hints.controls) {
      final found = _matchControl(candidates, control);
      if (found == null) {
        if (control.required) return null;
        continue;
      }
      matched[control.role] = found;
    }
    return matched;
  }

  /// מאתר דיאלוג שמבנהו תואם. המכל הנבדק הוא הדיאלוג עצמו וכן כל צאצא
  /// מאותה מחלקה — עמוד בתוך TabControl הוא `#32770` נוסף.
  static DiscoveredDialog? discoverDialog(int pid, DialogHints hints) {
    for (final dialog in candidateDialogs(pid, hints)) {
      final containers = <int>[
        dialog,
        ...ResponsaWin32.children(dialog).where(
          (c) => ResponsaWin32.className(c) == hints.windowClass,
        ),
      ];
      for (final container in containers) {
        final matched = _matchContainer(container, hints);
        if (matched != null && matched.isNotEmpty) {
          return DiscoveredDialog(
            hwnd: dialog,
            container: container,
            controls: matched,
          );
        }
      }
    }
    return null;
  }

  /// כל הדיאלוגים התואמים — נדרש למודאלים, שיכולים להצטבר.
  static List<DiscoveredDialog> discoverAll(int pid, DialogHints hints) => [
    for (final dialog in candidateDialogs(pid, hints, visibleOnly: true))
      if (_matchContainer(dialog, hints) case final matched?)
        DiscoveredDialog(
          hwnd: dialog,
          container: dialog,
          controls: matched,
        ),
  ];
}

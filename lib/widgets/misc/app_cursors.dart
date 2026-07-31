import 'dart:io';

import 'package:custom_mouse_cursor/custom_mouse_cursor.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

/// סמני אחיזה/גרירה משותפים (דפדוף בתצוגת ספר, סידור תוספים וכד').
///
/// ב-Windows אין grab/grabbing במנוע (flutter#99323), לכן נוצר שם סמן
/// מותאם מאייקון Fluent; בשאר הפלטפורמות משתמשים בסמני המערכת.
class AppCursors {
  AppCursors._();

  static MouseCursor _grab = Platform.isWindows
      ? SystemMouseCursors.click
      : SystemMouseCursors.grab;
  static MouseCursor _grabbing = Platform.isWindows
      ? SystemMouseCursors.click
      : SystemMouseCursors.grabbing;
  static bool _initStarted = false;

  /// יד פתוחה — ריחוף על אזור אחיז.
  static MouseCursor get grab => _grab;

  /// בזמן גרירה פעילה (ב-Windows זהה ל-[grab] — אין גליף אגרוף ב-Fluent).
  static MouseCursor get grabbing => _grabbing;

  /// יוצר את הסמנים המותאמים ברקע (חד-פעמי, Windows בלבד).
  /// עד לסיום — ואם היצירה נכשלת — נשארת יד המערכת (IDC_HAND).
  static Future<void> ensureInitialized() async {
    if (_initStarted || !Platform.isWindows) return;
    _initStarted = true;

    // הסמן חי מחוץ לערכת הנושא של האפליקציה — בסגנון סמני הדפדפן:
    // יד בהירה עם קו-מתאר כהה דק וחד (בלי הילת blur), קריא על כל רקע.
    const outline = [
      Shadow(color: Colors.black, offset: Offset(-1, 0)),
      Shadow(color: Colors.black, offset: Offset(1, 0)),
      Shadow(color: Colors.black, offset: Offset(0, -1)),
      Shadow(color: Colors.black, offset: Offset(0, 1)),
      Shadow(color: Colors.black, offset: Offset(-1, -1)),
      Shadow(color: Colors.black, offset: Offset(1, -1)),
      Shadow(color: Colors.black, offset: Offset(-1, 1)),
      Shadow(color: Colors.black, offset: Offset(1, 1)),
    ];

    try {
      final grabCursor = await CustomMouseCursor.icon(
        FluentIcons.hand_left_24_filled,
        size: 22,
        hotX: 11,
        hotY: 11,
        color: Colors.white,
        shadows: outline,
      );
      _grab = grabCursor;
      // אין גליף אגרוף ב-Fluent — אותה יד משמשת גם בזמן גרירה.
      _grabbing = grabCursor;
    } catch (e) {
      debugPrint('AppCursors: falling back to system cursor: $e');
    }
  }
}

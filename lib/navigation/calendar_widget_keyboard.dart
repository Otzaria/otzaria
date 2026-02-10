import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'calendar_cubit.dart';

/// Mixin שמוסיף תמיכה בניווט עם מקשי חיצים ללוח השנה
mixin CalendarKeyboardNavigation on State {
  late final FocusNode keyboardFocusNode;
  Timer? _keyRepeatTimer;
  LogicalKeyboardKey? _currentPressedKey;

  @override
  void initState() {
    super.initState();
    keyboardFocusNode = FocusNode(
      // מונע מהפוקוס לעבור ללחצנים אחרים
      skipTraversal: false,
      canRequestFocus: true,
    );

    // בקש פוקוס אוטומטי כשהווידג'ט נטען
    WidgetsBinding.instance.addPostFrameCallback((_) {
      keyboardFocusNode.requestFocus();
    });

    // האזן לשינויים בפוקוס ותמיד החזר אותו
    keyboardFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // אם הפוקוס אבד, החזר אותו
    if (!keyboardFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          keyboardFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _keyRepeatTimer?.cancel();
    keyboardFocusNode.removeListener(_onFocusChange);
    keyboardFocusNode.dispose();
    super.dispose();
  }

  /// מטפל באירועי מקלדת ומנווט בלוח השנה
  void handleCalendarKeyEvent(KeyEvent event, BuildContext context) {
    final cubit = context.read<CalendarCubit>();

    if (event is KeyDownEvent) {
      // לחיצה ראשונה - בצע פעולה מיד
      _executeNavigationAction(event.logicalKey, cubit);

      // התחל טיימר ללחיצה ארוכה (חזרה אוטומטית)
      _currentPressedKey = event.logicalKey;
      _keyRepeatTimer?.cancel();
      _keyRepeatTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_currentPressedKey != null) {
          _executeNavigationAction(_currentPressedKey!, cubit);
        }
      });
    } else if (event is KeyUpEvent) {
      // כשמשחררים את המקש, עצור את החזרה האוטומטית
      if (event.logicalKey == _currentPressedKey) {
        _keyRepeatTimer?.cancel();
        _currentPressedKey = null;
      }
    }
  }

  /// מבצע את פעולת הניווט בהתאם למקש
  void _executeNavigationAction(LogicalKeyboardKey key, CalendarCubit cubit) {
    if (key == LogicalKeyboardKey.arrowRight) {
      // חץ ימינה - יום קודם (RTL)
      cubit.navigateToPreviousDay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      // חץ שמאלה - יום הבא (RTL)
      cubit.navigateToNextDay();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      // חץ למעלה - שבוע קודם
      cubit.navigateToPreviousWeek();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      // חץ למטה - שבוע הבא
      cubit.navigateToNextWeek();
    }
  }

  /// עוטף ווידג'ט ב-KeyboardListener לתמיכה בניווט עם מקלדת
  Widget wrapWithKeyboardListener(Widget child) {
    return Focus(
      focusNode: keyboardFocusNode,
      autofocus: true,
      // מונע מהפוקוס לעבור החוצה
      onFocusChange: (hasFocus) {
        if (!hasFocus) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              keyboardFocusNode.requestFocus();
            }
          });
        }
      },
      child: KeyboardListener(
        focusNode: keyboardFocusNode,
        onKeyEvent: (event) => handleCalendarKeyEvent(event, context),
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Utility class for showing SnackBars throughout the app
///
/// For theme-aware colors, pass:
/// - Success: Theme.of(context).colorScheme.tertiaryContainer
/// - Error: Theme.of(context).colorScheme.error
/// - Warning: Theme.of(context).colorScheme.secondaryContainer
class UiSnack {
  /// Show a general SnackBar with the given message
  static void show(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  /// Show an error SnackBar with theme-aware error color
  static void showError(String message, {Color? backgroundColor}) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        backgroundColor: backgroundColor ?? Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Show a SnackBar with custom duration
  static void showWithDuration(String message,
      {Duration? duration, Color? backgroundColor}) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        duration: duration ?? const Duration(seconds: 4),
        backgroundColor: backgroundColor,
      ),
    );
  }

  /// Show a floating SnackBar
  static void showFloating(String message,
      {Duration? duration, Color? backgroundColor}) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 4),
        backgroundColor: backgroundColor,
      ),
    );
  }

  /// Show a SnackBar with an action button
  static void showWithAction({
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 8),
    Color? actionTextColor,
    Color? backgroundColor,
  }) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        duration: duration,
        backgroundColor: backgroundColor,
        action: SnackBarAction(
          label: actionLabel,
          textColor: actionTextColor,
          onPressed: onAction,
        ),
      ),
    );
  }

  /// Quick shortcuts for common Quick SnackBars
  static void showQuick(String message) {
    showWithDuration(message, duration: const Duration(milliseconds: 350));
  }

  static void showSuccess(String message, {Color? backgroundColor}) {
    showWithDuration(
      message,
      duration: const Duration(seconds: 2),
      backgroundColor: backgroundColor ?? Colors.green,
    );
  }

  /// Common messages constants (to avoid hardcoded strings)
  static const String textCopied = 'הטקסט הועתק ללוח';
  static const String formattedTextCopied = 'הטקסט המעוצב הועתק ללוח';
  static const String copyError = 'שגיאה בהעתקה';
  static const String formattedCopyError = 'שגיאה בהעתקה מעוצבת';
  static const String sectionNotFound = 'Section not found';
  static const String bookNotFound = 'הספר אינו קיים';
  static const String noteCreated = 'ההערה נוצרה והוצגה בסרגל';
  static const String savedSuccessfully = 'השינויים נשמרו בהצלחה';
  static const String textNotFound = 'הטקסט לא נמצא';
  static const String noTextSelected = 'אנא בחר טקסט להעתקה';
  static const String cleanupCompleted = 'ניקוי טיוטות הושלם';
}

/// Utility for routing Shamor Zachor messages through the global UI messenger.
class ShamorZachorMessenger {
  const ShamorZachorMessenger._();

  static void showInfo(String message) {
    UiSnack.show(message);
  }

  static void showSuccess(String message) {
    UiSnack.showSuccess(message);
  }

  static void showError(String message) {
    UiSnack.showError(message);
  }
}

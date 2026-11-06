import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/layout_tokens.dart';

double _logicalWidthOf(ui.FlutterView view) {
  if (view.devicePixelRatio == 0) {
    return LayoutBreakpoints.expanded;
  }
  return view.physicalSize.width / view.devicePixelRatio;
}

/// ברירת המחדל בלי הקשר: התצוגה הראשונה של התהליך.
double _currentLogicalScreenWidth() {
  final views = ui.PlatformDispatcher.instance.views;
  if (views.isEmpty) {
    return LayoutBreakpoints.expanded;
  }
  return _logicalWidthOf(views.first);
}

// בלי רישום תלות, כדי שיעבוד גם מ-initState ומ-create של provider.
ui.FlutterView? _viewOf(BuildContext context) =>
    context.findAncestorWidgetOfExactType<View>()?.view;

/// הרוחב הלוגי של התצוגה ש-[context] מוצג בה, ל-`screenWidth` של הפונקציות
/// כאן; null (= ברירת המחדל) כשאין View מעליו.
double? readingLayoutWidthOf(BuildContext context) {
  final view = _viewOf(context);
  return view == null ? null : _logicalWidthOf(view);
}

/// כמו [readingLayoutWidthOf], אך נמדד מחדש בכל קריאה — למחזיקים ארוכי-חיים
/// (התצוגה של הקשר קבועה; גודלה לא).
double? Function() readingLayoutWidthResolverOf(BuildContext context) {
  final view = _viewOf(context);
  return () => view == null ? null : _logicalWidthOf(view);
}

bool isCompactReadingLayout({double? screenWidth}) {
  final effectiveWidth = screenWidth ?? _currentLogicalScreenWidth();
  return effectiveWidth < LayoutBreakpoints.compact;
}

/// [hasSearchText] — טאב חדש שנפתח מחיפוש. אתחול הקורא אינו מחליט זאת שוב:
/// הוא רץ גם בשחזור טאב, ושם קובע המצב השמור (issue #4126).
bool shouldAutoOpenReadingLeftPane({
  double? screenWidth,
  bool hasSearchText = false,
}) {
  final isDefaultOpen =
      hasSearchText ||
      (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
      (Settings.getValue<bool>('key-default-sidebar-open') ?? false);
  if (!isDefaultOpen) {
    return false;
  }

  return !isCompactReadingLayout(screenWidth: screenWidth);
}

bool resolveInitialReadingLeftPaneVisibility({
  required bool explicitOpen,
  double? screenWidth,
}) {
  // הנעיצה אינה עוקפת מסך צר: שם החלונית היא overlay עם scrim שחוסם את
  // התוכן, וכפתור ביטול הנעיצה מוסתר.
  if ((Settings.getValue<bool>('key-pin-sidebar') ?? false) &&
      !isCompactReadingLayout(screenWidth: screenWidth)) {
    return true;
  }

  return explicitOpen;
}

bool resolveRestoredReadingLeftPaneState(
  Map<String, dynamic> json, {
  double? screenWidth,
}) {
  final savedShowLeftPane = json['showLeftPane'];
  if (savedShowLeftPane is bool) {
    return savedShowLeftPane;
  }

  return shouldAutoOpenReadingLeftPane(screenWidth: screenWidth);
}

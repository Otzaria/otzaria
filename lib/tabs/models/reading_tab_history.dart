import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

/// מחסניות החזרה/קדימה של טאב קריאה, לשמירה ברשומת היסטוריית הקריאה.
Map<String, Object>? readingTabNavigationHistory(OpenedTab tab) =>
    switch (tab) {
      TextBookTab() => tab.lines.historyToJson(),
      PdfBookTab() => tab.navigationHistoryToJson(),
      _ => null,
    };

/// מחזיר לטאב שנפתח מחדש את ההיסטוריה שנשמרה לספר. [asNewJump] — הטאב נפתח
/// ביעד מפורש ולא במיקום השמור.
void restoreReadingTabNavigationHistory(
  OpenedTab tab,
  Object? json, {
  bool asNewJump = false,
}) {
  switch (tab) {
    case TextBookTab():
      tab.lines.restoreHistory(json, asNewJump: asNewJump);
    case PdfBookTab():
      tab.navigationHistory.restore(json, asNewJump: asNewJump);
    default:
  }
}

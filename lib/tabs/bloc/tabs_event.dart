import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/tab.dart';

abstract class TabsEvent extends Equatable {
  const TabsEvent();

  @override
  List<Object?> get props => [];
}

class AddTab extends TabsEvent {
  final OpenedTab tab;
  // אם true – הטאב נכנס סמוך לטאב הנוכחי (cross-reference מתוך ספר פתוח).
  // אחרת – נוסף בסוף רשימת הטאבים, כברירת מחדל לפתיחת ספר חדש.
  final bool insertAdjacent;

  const AddTab(this.tab, {this.insertAdjacent = false});

  @override
  List<Object?> get props => [tab, insertAdjacent];
}

class OpenOrFocusTab extends TabsEvent {
  final OpenedTab tab;
  final String? targetTitle;
  final bool insertAdjacent;

  /// כשטאב קיים מאותר ועושים לו focus - האם להעביר אליו את המיקום (index/page)
  /// של הטאב הנכנס. משמש סימניות והיסטוריה - שם המשתמש בוחר מיקום ספציפי ולא
  /// רק את הספר, ולכן רוצים שהטאב הקיים ייגלל לאותו מיקום.
  final bool navigateToPositionIfReused;

  const OpenOrFocusTab(
    this.tab, {
    this.targetTitle,
    this.insertAdjacent = false,
    this.navigateToPositionIfReused = false,
  });

  @override
  List<Object?> get props => [
    tab,
    targetTitle,
    insertAdjacent,
    navigateToPositionIfReused,
  ];
}

/// החלפת טאב קיים בטאב אחר באותו מיקום — סיום רזולוציה של ResolvingTab.
class ReplaceTab extends TabsEvent {
  final OpenedTab oldTab;
  final OpenedTab newTab;

  const ReplaceTab({required this.oldTab, required this.newTab});

  @override
  List<Object?> get props => [oldTab, newTab];
}

class ReplaceAllTabs extends TabsEvent {
  final List<OpenedTab> tabs;
  final int currentTabIndex;

  const ReplaceAllTabs(this.tabs, this.currentTabIndex);

  @override
  List<Object?> get props => [tabs, currentTabIndex];
}

class SaveTabs extends TabsEvent {
  const SaveTabs();

  @override
  List<Object?> get props => [];
}

class RemoveTab extends TabsEvent {
  final OpenedTab tab;

  const RemoveTab(this.tab);

  @override
  List<Object?> get props => [tab];
}

/// סגירת קבוצת כרטיסיות בפעולה אחת (בחירה מרובה בשורת הכרטיסיות).
class RemoveTabs extends TabsEvent {
  final List<OpenedTab> tabs;

  const RemoveTabs(this.tabs);

  @override
  List<Object?> get props => [tabs];
}

/// צירוף/הסרה של כרטיסיה מהבחירה המרובה (Ctrl/Cmd+לחיצה).
class ToggleTabSelection extends TabsEvent {
  final OpenedTab tab;

  const ToggleTabSelection(this.tab);

  @override
  List<Object?> get props => [tab];
}

/// בחירת טווח מהכרטיסיה הפעילה עד [tab] (Shift+לחיצה).
class SelectTabRange extends TabsEvent {
  final OpenedTab tab;

  const SelectTabRange(this.tab);

  @override
  List<Object?> get props => [tab];
}

class ClearTabSelection extends TabsEvent {
  const ClearTabSelection();
}

class CloseCurrentTab extends TabsEvent {
  const CloseCurrentTab();

  @override
  List<Object?> get props => [];
}

class RestoreLastClosedTab extends TabsEvent {
  const RestoreLastClosedTab();

  @override
  List<Object?> get props => [];
}

class SetCurrentTab extends TabsEvent {
  final int index;

  const SetCurrentTab(this.index);

  @override
  List<Object?> get props => [index];
}

class CloseAllTabs extends TabsEvent {}

class CloseOtherTabs extends TabsEvent {
  final OpenedTab keepTab;

  const CloseOtherTabs(this.keepTab);

  @override
  List<Object?> get props => [keepTab];
}

class CloneTab extends TabsEvent {
  final OpenedTab tab;

  const CloneTab(this.tab);

  @override
  List<Object?> get props => [tab];
}

class MoveTab extends TabsEvent {
  final OpenedTab tab;
  final int newIndex;

  const MoveTab(this.tab, this.newIndex);

  @override
  List<Object?> get props => [tab, newIndex];
}

class NavigateToNextTab extends TabsEvent {}

class NavigateToPreviousTab extends TabsEvent {}

class LoadTabs extends TabsEvent {}

/// ממפה נתיבי קבצים של הטאבים הפתוחים מתיקיית ספרייה ישנה לחדשה, אחרי
/// העברת מיקום הספרייה, כדי שספרי PDF/DOCX פתוחים ייטענו מהמיקום החדש.
///
/// [completer] מאפשר להמתין לסיום ה-handler (עדכון הזיכרון + שמירה ל-Hive)
/// לפני שממשיכים לרענון, כדי שלא ייווצר race שבו שמירת הטאבים בעת ה-dispose
/// תדרוס את המיפוי עם הנתיב הישן. מוחרג מ-props (לא משפיע על שוויון האירוע).
class RemapBookPaths extends TabsEvent {
  final String fromDir;
  final String toDir;
  final Completer<void>? completer;

  const RemapBookPaths(this.fromDir, this.toDir, {this.completer});

  @override
  List<Object?> get props => [fromDir, toDir];
}

class TogglePinTab extends TabsEvent {
  final OpenedTab tab;

  const TogglePinTab(this.tab);

  @override
  List<Object?> get props => [tab];
}

/// מיזוג שני טאבים פתוחים לטאב אחד המציג אותם זה לצד זה.
///
/// שניהם יוצאים משורת הכרטיסיות והטאב המפוצל נכנס במקומם, בלי לשכפל אותם —
/// כך מיקום הקריאה בכל אחד מהם נשמר.
class EnableSideBySideMode extends TabsEvent {
  /// הטאב שיוצג בחלונית הראשונה (הימנית ב-RTL).
  final OpenedTab rightTab;

  /// הטאב שיוצג בחלונית השנייה (השמאלית ב-RTL).
  final OpenedTab leftTab;

  const EnableSideBySideMode({required this.rightTab, required this.leftTab});

  @override
  List<Object?> get props => [rightTab, leftTab];
}

/// פירוק טאב מפוצל לשתי כרטיסיות עצמאיות.
class DisableSideBySideMode extends TabsEvent {
  final int tabIndex;
  const DisableSideBySideMode(this.tabIndex);

  @override
  List<Object?> get props => [tabIndex];
}

/// חלקה של החלונית הראשונה מרוחב הטאב המפוצל הנוכחי.
class UpdateSplitRatio extends TabsEvent {
  final double ratio;

  const UpdateSplitRatio(this.ratio);

  @override
  List<Object?> get props => [ratio];
}

/// החלפת הצדדים בטאב מפוצל.
class SwapSideBySideTabs extends TabsEvent {
  /// הטאב שצדדיו יוחלפו. `null` = הטאב הפעיל.
  final int? tabIndex;

  const SwapSideBySideTabs({this.tabIndex});

  @override
  List<Object?> get props => [tabIndex];
}

/// סימון החלונית שהמשתמש עובד בה בטאב הנוכחי.
///
/// נשלח בלחיצה בתוך חלונית. הפוקוס, ניווט מסימניה ושכבת התוספים נגזרים ממנה —
/// בלעדיה כל חלוניות הטאב נחשבו "בחזית" והתחרו על פוקוס המקלדת.
///
/// החלונית עצמה ולא נתיבה: נתיב מתיישן בכל שינוי מבנה.
class SetActivePane extends TabsEvent {
  final OpenedTab pane;

  const SetActivePane(this.pane);

  @override
  List<Object?> get props => [pane];
}

/// סגירת חלונית אחת מטאב מפוצל; אחותה נשארת ככרטיסייה רגילה במקומו.
class ClosePane extends TabsEvent {
  /// החלונית עצמה ולא מיקומה: מיקום מתיישן בכל שינוי בשורת הכרטיסיות.
  final OpenedTab pane;

  const ClosePane(this.pane);

  @override
  List<Object?> get props => [pane];
}

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

  /// פתיחה ברקע ("פתח בכרטיסייה חדשה"): הטאב נוסף אך המשתמש נשאר על הנוכחי.
  final bool inBackground;

  const AddTab(
    this.tab, {
    this.insertAdjacent = false,
    this.inBackground = false,
  });

  @override
  List<Object?> get props => [tab, insertAdjacent, inBackground];
}

class OpenOrFocusTab extends TabsEvent {
  final OpenedTab tab;
  final String? targetTitle;
  final bool insertAdjacent;

  /// כשטאב קיים מאותר ועושים לו focus - האם להעביר אליו את המיקום (index/page)
  /// של הטאב הנכנס. משמש סימניות והיסטוריה - שם המשתמש בוחר מיקום ספציפי ולא
  /// רק את הספר, ולכן רוצים שהטאב הקיים ייגלל לאותו מיקום.
  final bool navigateToPositionIfReused;

  /// פתיחה ברקע: תמיד טאב חדש (בלי מיקוד טאב קיים), והמשתמש נשאר על הנוכחי.
  final bool inBackground;

  const OpenOrFocusTab(
    this.tab, {
    this.targetTitle,
    this.insertAdjacent = false,
    this.navigateToPositionIfReused = false,
    this.inBackground = false,
  });

  @override
  List<Object?> get props => [
    tab,
    targetTitle,
    insertAdjacent,
    navigateToPositionIfReused,
    inBackground,
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

  /// צד החלונית הפעילה בטאב שב-[currentTabIndex] (`'right'`/`'left'`),
  /// או `null` כשאין — ואז החלונית הפעילה נופלת ל-`panes.first`.
  final String? activePane;

  const ReplaceAllTabs(this.tabs, this.currentTabIndex, {this.activePane});

  @override
  List<Object?> get props => [tabs, currentTabIndex, activePane];
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

/// משחזר כרטיסיה מסוימת מרשימת הנסגרות לאחרונה, לפי המופע שנשמר בה
/// (`TabsBloc.recentlyClosedTabs`).
class RestoreClosedTab extends TabsEvent {
  final OpenedTab tab;

  const RestoreClosedTab(this.tab);

  @override
  List<Object?> get props => [tab];
}

/// מנקה את רשימת הכרטיסיות שנסגרו לאחרונה
/// (`TabsBloc.recentlyClosedTabs`) ומשחרר את המופעים השמורים בה.
class ClearRecentlyClosedTabs extends TabsEvent {
  const ClearRecentlyClosedTabs();

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

/// חלון שהוחזר לשימוש מאמץ כרטיסיה שנגררה אליו, במקום כל מה שהיה בו.
///
/// ⚠️ **אירוע אחד, ולא [CloseAllTabs] ואחריו [AddTab].** הצמד יצר מצב
/// ביניים של אפס כרטיסיות, ו-`ReadingScreen` מאזין בדיוק למעבר הזה
/// (`previous.hasOpenTabs && !current.hasOpenTabs`) כדי לנווט למסך
/// הספרייה — כלומר החלון נחת בספרייה ולא על הכרטיסיה שנגררה אליו.
///
/// זה קרה **רק** בחלון שכבר היה פתוח ונסגר: פתיחה ראשונה עוברת בנקודת
/// הכניסה של החלון המשני ואין בה כרטיסיות קודמות, ולכן אין מעבר.
///
/// הכרטיסיות המוצמדות נשמרות, בדיוק כמו ב-[CloseAllTabs].
class AdoptTab extends TabsEvent {
  const AdoptTab(this.tab);

  final OpenedTab tab;

  @override
  List<Object?> get props => [tab];
}

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

/// שינוי כותרת של טאב פתוח (גם חלונית בתוך טאב מפוצל) בלי להחליף אותו.
class RenameTab extends TabsEvent {
  final OpenedTab tab;
  final String title;

  const RenameTab(this.tab, this.title);

  @override
  List<Object?> get props => [tab, title];
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
class CreateCombinedTab extends TabsEvent {
  /// הטאב שיוצג בחלונית הראשונה (הימנית ב-RTL).
  final OpenedTab rightTab;

  /// הטאב שיוצג בחלונית השנייה (השמאלית ב-RTL).
  final OpenedTab leftTab;

  const CreateCombinedTab({required this.rightTab, required this.leftTab});

  @override
  List<Object?> get props => [rightTab, leftTab];
}

/// פתיחת [tab] כחלונית נוספת בטאב הנוכחי, במקום ככרטיסייה חדשה.
///
/// הטאב הנוכחי נשאר במקומו כחלונית הימנית (ב-RTL) והחדש נכנס לצידו.
class OpenTabInSidePane extends TabsEvent {
  final OpenedTab tab;

  const OpenTabInSidePane(this.tab);

  @override
  List<Object?> get props => [tab];
}

/// פירוק טאב מפוצל לשתי כרטיסיות עצמאיות.
class ExpandCombinedTab extends TabsEvent {
  final int tabIndex;
  const ExpandCombinedTab(this.tabIndex);

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

/// הוצאת חלונית מטאב מפוצל חזרה לשורת הכרטיסיות, במיקום ההכנסה שנבחר.
///
/// אחות החלונית תופסת את מקום הטאב המפוצל, והחלונית עצמה — בזהותה, כדי
/// לשמר את מצב הקריאה — נכנסת ככרטיסייה עצמאית ב-[insertIndex].
class DetachPane extends TabsEvent {
  /// החלונית עצמה ולא מיקומה: מיקום מתיישן בכל שינוי בשורת הכרטיסיות.
  final OpenedTab pane;

  /// מיקום ההכנסה בשורת הכרטיסיות (0 עד אורך הרשימה).
  final int insertIndex;

  const DetachPane(this.pane, {required this.insertIndex});

  @override
  List<Object?> get props => [pane, insertIndex];
}

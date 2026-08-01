import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

/// מצב הצגת 2 ספרים זה לצד זה
class SideBySideMode extends Equatable {
  final int leftTabIndex;
  final int rightTabIndex;
  final double splitRatio; // 0.0-1.0, כמה מהמסך תופס הספר הימני

  const SideBySideMode({
    required this.leftTabIndex,
    required this.rightTabIndex,
    this.splitRatio = 0.5,
  });

  SideBySideMode copyWith({
    int? leftTabIndex,
    int? rightTabIndex,
    double? splitRatio,
  }) {
    return SideBySideMode(
      leftTabIndex: leftTabIndex ?? this.leftTabIndex,
      rightTabIndex: rightTabIndex ?? this.rightTabIndex,
      splitRatio: splitRatio ?? this.splitRatio,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'leftTabIndex': leftTabIndex,
      'rightTabIndex': rightTabIndex,
      'splitRatio': splitRatio,
    };
  }

  factory SideBySideMode.fromJson(Map<String, dynamic> json) {
    return SideBySideMode(
      leftTabIndex: json['leftTabIndex'] as int,
      rightTabIndex: json['rightTabIndex'] as int,
      splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? 0.5,
    );
  }

  @override
  List<Object?> get props => [leftTabIndex, rightTabIndex, splitRatio];
}

class TabsState extends Equatable {
  final List<OpenedTab> tabs;
  final int currentTabIndex;
  final int updateCounter;
  final SideBySideMode? sideBySideMode;

  /// בחירה מרובה לסגירה קבוצתית (Ctrl/Shift+לחיצה בשורת הכרטיסיות).
  /// מצב זמני — אינו נשמר לדיסק.
  final List<OpenedTab> selectedTabs;

  /// החלונית שהמשתמש עובד בה, כפי שנקבעה בלחיצה אחרונה.
  ///
  /// נשמרת כזהות אובייקט ולא כנתיב: נתיב מתיישן בכל שינוי מבנה — סגירת חלונית
  /// מקוננת מקצרת אותו, החלפת צדדים הופכת את משמעותו, ונתיב מטאב אחר עלול
  /// להיות "תקין במקרה" ולסמן ספר שהמשתמש לא נגע בו. זהות נוסעת עם החלונית.
  ///
  /// נקרא דרך [activePane].
  final OpenedTab? rawActivePane;

  /// החלונית הקוראת האחרונה — ראו [readingPane]. מתוחזק אוטומטית ב-[copyWith]
  /// ולא על-ידי המטפלים.
  final OpenedTab? lastReadingPane;

  const TabsState({
    required this.tabs,
    required this.currentTabIndex,
    this.updateCounter = 0,
    this.sideBySideMode,
    this.selectedTabs = const [],
    this.rawActivePane,
    this.lastReadingPane,
  });

  factory TabsState.initial() {
    return const TabsState(
      tabs: [],
      currentTabIndex: 0,
      updateCounter: 0,
      sideBySideMode: null,
    );
  }

  TabsState copyWith({
    List<OpenedTab>? tabs,
    int? currentTabIndex,
    bool forceUpdate = false,
    SideBySideMode? sideBySideMode,
    bool clearSideBySide = false,
    List<OpenedTab>? selectedTabs,
    OpenedTab? rawActivePane,
  }) {
    final nextTabs = tabs ?? this.tabs;
    final nextIndex = currentTabIndex ?? this.currentTabIndex;
    final nextRawActivePane = rawActivePane ?? this.rawActivePane;
    return TabsState(
      tabs: nextTabs,
      currentTabIndex: nextIndex,
      updateCounter: forceUpdate ? updateCounter + 1 : updateCounter,
      sideBySideMode: clearSideBySide
          ? null
          : (sideBySideMode ?? this.sideBySideMode),
      selectedTabs: selectedTabs ?? this.selectedTabs,
      rawActivePane: nextRawActivePane,
      lastReadingPane: _resolveLastReadingPane(
        tabs: nextTabs,
        currentTabIndex: nextIndex,
        rawActivePane: nextRawActivePane,
        previous: lastReadingPane,
      ),
    );
  }

  /// חלונית קריאה = כל חלונית שאינה טאב כלי. טאב כלי אינו מקום קריאה, ולכן
  /// אסור שהוא ידרוס את ההקשר שהתוסף שנפתח בא לקרוא.
  static bool _isReadingPane(OpenedTab? pane) =>
      pane != null && pane is! ToolTab;

  static OpenedTab? _resolveActivePane(
    List<OpenedTab> tabs,
    int currentTabIndex,
    OpenedTab? rawActivePane,
  ) {
    if (tabs.isEmpty) return null;
    if (currentTabIndex < 0 || currentTabIndex >= tabs.length) return null;
    final tab = tabs[currentTabIndex];
    final panes = leafPanes(tab);
    if (rawActivePane != null &&
        panes.any((pane) => identical(pane, rawActivePane))) {
      return rawActivePane;
    }
    return panes.first;
  }

  static OpenedTab? _resolveLastReadingPane({
    required List<OpenedTab> tabs,
    required int currentTabIndex,
    required OpenedTab? rawActivePane,
    required OpenedTab? previous,
  }) {
    final active = _resolveActivePane(tabs, currentTabIndex, rawActivePane);
    if (_isReadingPane(active)) return active;
    // הטאב הפעיל הוא כלי; מעדיפים חלונית ספר שנמצאת באותו טאב מפוצל.
    if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
      for (final pane in leafPanes(tabs[currentTabIndex])) {
        if (_isReadingPane(pane)) return pane;
      }
    }
    // נופלים לחלונית הקוראת הקודמת, כל עוד היא עדיין פתוחה.
    if (previous == null) return null;
    for (final tab in tabs) {
      if (leafPanes(tab).contains(previous)) return previous;
    }
    return null;
  }

  bool get hasOpenTabs => tabs.isNotEmpty;
  OpenedTab? get currentTab => hasOpenTabs ? tabs[currentTabIndex] : null;
  bool get isSideBySideMode => sideBySideMode != null;

  /// החלונית שהמשתמש עובד בה. בטאב שאינו מפוצל — הטאב עצמו.
  ///
  /// חלונית ששמורה מטאב אחר, או שנסגרה, אינה נמצאת בעץ הנוכחי ולכן נופלת
  /// לחלונית הראשונה שלו. כך אין צורך לנרמל את השדה בכל מטפל שמשנה מבנה.
  OpenedTab? get activePane =>
      _resolveActivePane(tabs, currentTabIndex, rawActivePane);

  /// החלונית שממנה נגזר מיקום הקריאה עבור ה-API של התוספים ולהיסטוריה.
  ///
  /// זהה ל-[activePane] בכל מקרה, למעט טאב כלי: תוסף שנפתח מתפריט ההקשר של
  /// ספר חייב להמשיך לקרוא את מיקום הספר וההדגשה שבגללם נפתח, ולכן טאב כלי
  /// מדלג אל חלונית הספר שבאותו טאב מפוצל, ואם אין — אל הקודמת שנשמרה.
  OpenedTab? get readingPane {
    final pane = activePane;
    if (_isReadingPane(pane)) return pane;
    return lastReadingPane;
  }

  /// הקבוצה שסגירת הכרטיסיה הנוכחית סוגרת: הבחירה המרובה כשהכרטיסיה
  /// הפעילה חלק ממנה, אחרת הכרטיסיה הפעילה לבדה.
  List<OpenedTab> get currentCloseGroup {
    final current = currentTab;
    if (current == null) return const [];
    if (selectedTabs.length > 1 && selectedTabs.contains(current)) {
      return List<OpenedTab>.from(selectedTabs);
    }
    return [current];
  }

  @override
  List<Object?> get props => [
    tabs,
    currentTabIndex,
    updateCounter,
    sideBySideMode,
    selectedTabs,
    rawActivePane,
    lastReadingPane,
  ];
}

import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

/// עדכון החלונית הפעילה ב-[TabsState.copyWith].
///
/// פרמטר `OpenedTab? rawActivePane` עם `?? this.rawActivePane` לא ידע להבחין
/// בין "אל תיגע" לבין "נקה": `null` תמיד נקרא כ"אל תיגע". לכן מעבר לטאב שבו
/// אין חלונית מתאימה השאיר את החלונית הפעילה של טאב **אחר**.
sealed class ActivePaneUpdate {
  const ActivePaneUpdate();

  /// השאר את החלונית הפעילה כפי שהיא.
  const factory ActivePaneUpdate.unchanged() = _ActivePaneUnchanged;

  /// אין חלונית פעילה מפורשת — [TabsState.activePane] ייפול ל-`panes.first`.
  const factory ActivePaneUpdate.clear() = _ActivePaneClear;

  /// קבע את [pane] כחלונית הפעילה.
  const factory ActivePaneUpdate.set(OpenedTab pane) = _ActivePaneSet;
}

final class _ActivePaneUnchanged extends ActivePaneUpdate {
  const _ActivePaneUnchanged();
}

final class _ActivePaneClear extends ActivePaneUpdate {
  const _ActivePaneClear();
}

final class _ActivePaneSet extends ActivePaneUpdate {
  const _ActivePaneSet(this.pane);

  final OpenedTab pane;
}

class TabsState extends Equatable {
  final List<OpenedTab> tabs;
  final int currentTabIndex;
  final int updateCounter;

  /// בחירה מרובה זמנית לסגירה קבוצתית.
  final List<OpenedTab> selectedTabs;

  /// החלונית הפעילה נשמרת כזהות אובייקט כדי לא להתיישן בשינוי מבנה.
  final OpenedTab? rawActivePane;

  /// חלונית הקריאה האחרונה, לשמירת הקשר בעת פתיחת כלי.
  final OpenedTab? lastReadingPane;

  const TabsState({
    required this.tabs,
    required this.currentTabIndex,
    this.updateCounter = 0,
    this.selectedTabs = const [],
    this.rawActivePane,
    this.lastReadingPane,
  });

  factory TabsState.initial() {
    return const TabsState(tabs: [], currentTabIndex: 0, updateCounter: 0);
  }

  /// [forceUpdate] רק לטאב ששונה במקום: הוא בונה מחדש את תוכן כל הכרטיסיות
  /// הפתוחות. טאב חדש ברשימה נבנה ממילא.
  TabsState copyWith({
    List<OpenedTab>? tabs,
    int? currentTabIndex,
    bool forceUpdate = false,
    List<OpenedTab>? selectedTabs,
    ActivePaneUpdate activePane = const ActivePaneUpdate.unchanged(),
  }) {
    final nextTabs = tabs ?? this.tabs;
    final nextIndex = currentTabIndex ?? this.currentTabIndex;
    final nextRawActivePane = switch (activePane) {
      _ActivePaneUnchanged() => rawActivePane,
      _ActivePaneClear() => null,
      _ActivePaneSet(:final pane) => pane,
    };
    return TabsState(
      tabs: nextTabs,
      currentTabIndex: nextIndex,
      updateCounter: forceUpdate ? updateCounter + 1 : updateCounter,
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

  /// טאב כלי אינו מייצג מיקום קריאה.
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
    // כלי מפוצל משתמש בהקשר הקריאה של החלונית האחות.
    if (currentTabIndex >= 0 && currentTabIndex < tabs.length) {
      for (final pane in leafPanes(tabs[currentTabIndex])) {
        if (_isReadingPane(pane)) return pane;
      }
    }
    // משתמשים בהקשר הקודם רק אם הוא עדיין פתוח.
    if (previous == null) return null;
    for (final tab in tabs) {
      // identity by design: [OpenedTab] אינו דורס `operator ==`, ולכן
      // `contains` משווה זהות אובייקט — בדיוק כמו [_resolveActivePane].
      // מי שיוסיף `==` מבוסס-מזהה חייב להחליף כאן ל-`identical`, אחרת שני
      // עותקים של אותו ספר ייחשבו לאותה חלונית.
      if (leafPanes(tab).contains(previous)) return previous;
    }
    return null;
  }

  bool get hasOpenTabs => tabs.isNotEmpty;
  OpenedTab? get currentTab => hasOpenTabs ? tabs[currentTabIndex] : null;

  /// החלונית הפעילה, או החלונית הראשונה בטאב הנוכחי.
  OpenedTab? get activePane =>
      _resolveActivePane(tabs, currentTabIndex, rawActivePane);

  /// החלונית שממנה נגזר מיקום הקריאה לתוספים ולהיסטוריה.
  /// בטאב כלי מוחזר הקשר הקריאה האחרון.
  OpenedTab? get readingPane {
    final pane = activePane;
    if (_isReadingPane(pane)) return pane;
    return lastReadingPane;
  }

  /// צד החלונית הפעילה בטאב הנוכחי, לשמירה בשולחן עבודה.
  /// `null` כשהטאב הנוכחי אינו מפוצל — ואז אין מה לשמר.
  ///
  /// נשמר כצד ולא כאובייקט משום ששולחן עבודה משכפל את הטאבים בשמירה
  /// (`WorkspaceBloc._cloneTabs`), וזהות האובייקט אובדת ממילא.
  String? get activePaneSide {
    final tab = currentTab;
    if (tab == null) return null;
    return activePaneSideOf(tab, activePane);
  }

  /// קבוצת הכרטיסיות שהסגירה הנוכחית חלה עליה.
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
    selectedTabs,
    rawActivePane,
    lastReadingPane,
  ];
}

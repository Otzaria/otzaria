import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

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

  TabsState copyWith({
    List<OpenedTab>? tabs,
    int? currentTabIndex,
    bool forceUpdate = false,
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

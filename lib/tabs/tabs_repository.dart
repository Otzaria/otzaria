import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';
import 'package:flutter/foundation.dart';

/// מצב הסשן של חלון אחד: המשבצת שלו, דור הסשן והאינדקס שממתין לכתיבה.
///
/// ⚠️ שייך לחלון ולא למאגר: הסגירה, הייבוא מגיבוי ו-`TabsBloc` פונים אליו
/// דרך מופעים שונים של [TabsRepository], וחייבים לראות אותו מצב.
class WindowTabsSession {
  WindowTabsSession({int? Function()? slot})
    : _slot = slot ?? (() => UserStateSlot.main);

  /// הסשן של החלון הראשי; לכל חלון Dart נוסף סשן משלו.
  static final WindowTabsSession current = WindowTabsSession();

  final int? Function() _slot;

  /// המשבצת שהחלון הזה כותב אליה, או null כשאינו יכול לשמור.
  ///
  /// ⚠️ חלון בלי משבצת אינו שומר, ובשום מצב אינו נופל למשבצת של חלון אחר
  /// — זו הייתה דריסת הכרטיסיות שלו.
  int? get slot => _suspended ? null : _slot();

  bool _suspended = false;

  /// חלון מוסתר שהסשן שלו נמחק אינו שומר עד שיוצג שוב ([resume]).
  void suspend() {
    _suspended = true;
    _cancelPendingIndex();
  }

  void resume() => _suspended = false;

  /// דור הסשן של החלון: עולה בהחלפת עץ הטאבים או בייבוא מגיבוי.
  int get generation => _generation;
  int _generation = 0;

  /// מקצה לעץ החדש דור שמירה; אירועי העץ הקודם אינם שומרים עוד.
  int beginRuntime() => ++_generation;

  /// האינדקס הפעיל שממתין לכתיבה, והמשבצת שאליה.
  Timer? _indexTimer;
  int? _pendingIndex;
  int? _pendingIndexSlot;

  void _cancelPendingIndex() {
    _indexTimer?.cancel();
    _indexTimer = null;
    _pendingIndex = null;
    _pendingIndexSlot = null;
  }
}

class TabsRepository {
  TabsRepository({this.sessions, WindowTabsSession? window})
    : window = window ?? WindowTabsSession.current;

  /// השהיית הכתיבה של האינדקס הפעיל. זו הפעולה השכיחה ביותר — מעבר מהיר
  /// בין כרטיסיות מתמזג לכתיבה אחת.
  static const Duration _indexDebounce = Duration(milliseconds: 300);

  /// מאגר הסשנים שכל המופעים ייפלו אליו; לבדיקות בלבד.
  @visibleForTesting
  static WindowSessionStore? debugSessions;

  /// מאגר הסשנים של המופע הזה; null = המאגר הגלובלי.
  final WindowSessionStore? sessions;

  /// החלון שהמאגר הזה שומר את הסשן שלו.
  final WindowTabsSession window;

  WindowSessionStore get _store =>
      sessions ?? debugSessions ?? WindowSessionStore.instance;

  static WindowSessionStore get _staticStore =>
      debugSessions ?? WindowSessionStore.instance;

  int? get _sessionSlot => window.slot;

  /// דור הסשן של החלון הזה: עולה בכל [importRaw]. `TabsBloc` שנבנה לפני
  /// הייבוא אינו שומר יותר — אחרת סגירתו בעת ההפעלה מחדש הייתה כותבת את
  /// הכרטיסיות שבזיכרונו על אלה ששוחזרו.
  static int get sessionGeneration => WindowTabsSession.current.generation;

  /// הטאבים הפתוחים והטאב הפעיל, גולמיים, לגיבוי; null כשאין משבצת.
  ///
  /// גולמי (ה-JSON כפי שנשמר) ולא [OpenedTab]: טאב שאינו נטען במחשב היעד
  /// (ספר חסר) מדולג בטעינה על ידי [loadTabs], ואין להשמיט אותו מהגיבוי מראש.
  Future<Map<String, dynamic>?> exportRaw() async {
    final slot = _sessionSlot;
    if (slot == null) return null;
    final session = await _store.load(slot);
    return {
      'tabs': session == null ? <dynamic>[] : _decodeTabs(session.tabsJson),
      'currentTab': session?.currentIndex ?? 0,
    };
  }

  /// כתיבת הטאבים מגיבוי לסשן של החלון הזה, בדריסת הטאבים השמורים.
  Future<void> importRaw(Map<String, dynamic> data) async {
    final slot = _sessionSlot;
    if (slot == null) return;
    final tabs = data['tabs'];
    final current = data['currentTab'];
    window._cancelPendingIndex();
    await _store.save(
      slot,
      tabsJson: jsonEncode(tabs is List ? tabs : <dynamic>[]),
      currentIndex: current is int ? current : 0,
    );
    window._generation++;
  }

  static List<dynamic> _decodeTabs(String tabsJson) {
    final decoded = jsonDecode(tabsJson);
    return decoded is List ? decoded : const [];
  }

  int _resolvePersistedCurrentTabIndex(
    Map<int, int> persistedIndexByOriginalIndex,
    int currentTabIndex,
    int originalTabsCount,
  ) {
    if (persistedIndexByOriginalIndex.isEmpty) return 0;
    currentTabIndex = currentTabIndex.clamp(0, originalTabsCount - 1);

    final directMatch = persistedIndexByOriginalIndex[currentTabIndex];
    if (directMatch != null) return directMatch;

    for (var i = currentTabIndex - 1; i >= 0; i--) {
      final previousMatch = persistedIndexByOriginalIndex[i];
      if (previousMatch != null) return previousMatch;
    }

    for (var i = currentTabIndex + 1; i < originalTabsCount; i++) {
      final nextMatch = persistedIndexByOriginalIndex[i];
      if (nextMatch != null) return nextMatch;
    }

    return 0;
  }

  /// ממפה נתיבי קבצים של טאבים פתוחים *בזיכרון* מ-[fromDir] ל-[toDir].
  /// טאב שהנתיב שלו לא משתנה מוחזר כאובייקט המקורי (ללא בנייה מחדש);
  /// טאב ששונה נבנה מחדש דרך toJson→fromJson עם הנתיב החדש.
  /// ⚠️ מיפוי במסד בלבד אינו מספיק: שמירת הטאבים שבזיכרון בעת dispose
  /// דורסת אותו, ולכן ספר PDF היה נטען מהנתיב הישן.
  List<OpenedTab> remapTabsInMemory(
    List<OpenedTab> tabs,
    String fromDir,
    String toDir,
  ) {
    return tabs.map((tab) {
      var changed = false;
      final remappedJson = _remapNode(
        tab.toJson(),
        fromDir,
        toDir,
        () => changed = true,
      );
      if (!changed) return tab;
      return OpenedTab.fromJson(castMap(remappedJson));
    }).toList();
  }

  dynamic _remapNode(
    dynamic node,
    String fromDir,
    String toDir,
    void Function() onChange,
  ) {
    if (node is Map) {
      final result = <String, dynamic>{};
      node.forEach((key, value) {
        final k = key.toString();
        if ((k == 'path' || k == 'filePath') &&
            value is String &&
            value.isNotEmpty &&
            (p.equals(fromDir, value) || p.isWithin(fromDir, value))) {
          result[k] = p.join(toDir, p.relative(value, from: fromDir));
          onChange();
        } else {
          result[k] = _remapNode(value, fromDir, toDir, onChange);
        }
      });
      return result;
    }
    if (node is List) {
      return node.map((e) => _remapNode(e, fromDir, toDir, onChange)).toList();
    }
    return node;
  }

  /// הטאבים כפי שנשמרו בסשן של החלון הזה. פיצול מקונן מגרסה קודמת מנורמל
  /// אצל הקורא דרך [flattenRestoredSplits], יחד עם האינדקס הפעיל.
  ///
  /// ⚠️ **כל חלון משחזר את הסשן של המשבצת שלו**, משני כראשי: סשן שנשאר
  /// במשבצת פירושו חלון שמת בלי סגירה מסודרת, והכרטיסיות שבו פתוחות
  /// מבחינת המשתמש. סגירה יזומה מוחקת אותו ([discardWindowSession]),
  /// ולכן חלון חדש אינו יורש שרידים של חלון שנסגר.
  ///
  /// [newRuntime] מנתק את זהות התוספים מעץ קודם שעשוי עדיין להתפרק.
  /// ⚠️ סינכרוני — נקרא מבנאי של bloc. מחייב שהמסד כבר נפתח באתחול.
  List<OpenedTab> loadTabs({bool newRuntime = false}) {
    _restoredCurrentIndex = null;
    final slot = _sessionSlot;
    if (slot == null) return const [];
    try {
      final session = _store.loadOpened(slot);
      if (session == null) return const [];
      final tabs = <OpenedTab>[];
      final indexByOriginal = <int, int>{};
      final rawTabs = _decodeTabs(session.tabsJson);
      for (var i = 0; i < rawTabs.length; i++) {
        try {
          final json = castMap(rawTabs[i]);
          tabs.add(
            OpenedTab.fromJson(
              newRuntime ? OpenedTab.withNewRuntimeIdentity(json) : json,
            ),
          );
          indexByOriginal[i] = tabs.length - 1;
        } catch (tabError) {
          debugPrint('⚠️ Skipping tab that failed to restore: $tabError');
        }
      }
      _restoredCurrentIndex = _resolvePersistedCurrentTabIndex(
        indexByOriginal,
        session.currentIndex,
        rawTabs.length,
      );
      return tabs;
    } catch (e) {
      debugPrint('⚠️ Error loading tabs from disk: $e');
      return [];
    }
  }

  /// האינדקס הפעיל ממופה לטאבים ש-[loadTabs] האחרון החזיר; נצרך פעם אחת.
  int? _restoredCurrentIndex;

  int loadCurrentTabIndex() {
    final restored = _restoredCurrentIndex;
    _restoredCurrentIndex = null;
    if (restored != null) return restored;
    final slot = _sessionSlot;
    if (slot == null) return 0;
    try {
      return _store.loadOpened(slot)?.currentIndex ?? 0;
    } catch (e) {
      debugPrint('⚠️ Error loading current tab index: $e');
      return 0;
    }
  }

  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {
    final slot = _sessionSlot;
    if (slot == null) {
      debugPrint('⚠️ saveTabs: אין משבצת לחלון הזה — הסשן לא נשמר');
      return;
    }
    final persistedIndexByOriginalIndex = <int, int>{};
    for (var i = 0; i < tabs.length; i++) {
      persistedIndexByOriginalIndex[i] = i;
    }
    final persistedCurrentIndex = _resolvePersistedCurrentTabIndex(
      persistedIndexByOriginalIndex,
      currentTabIndex,
      tabs.length,
    );
    // הכתיבה המלאה נושאת גם את האינדקס, ולכן היא מחליפה כתיבה ממתינה.
    window._cancelPendingIndex();
    await _store.save(
      slot,
      tabsJson: jsonEncode(tabs.map((tab) => tab.toJson()).toList()),
      currentIndex: persistedCurrentIndex,
    );
  }

  /// מוחק את סשן החלון הזה — כשהמשתמש סוגר חלון שאינו האחרון, אחרי
  /// ה-flush. בלי המחיקה ההפעלה הבאה הייתה מחזירה כרטיסיות שנסגרו במכוון.
  Future<void> discardWindowSession() async {
    final slot = _sessionSlot;
    if (slot == null) return;
    try {
      window._cancelPendingIndex();
      await _store.delete(slot);
    } catch (e) {
      debugPrint('⚠️ discardWindowSession failed: $e');
    }
  }

  /// מצרף לחלון הראשון סשנים שנשארו מחלונות שמתו בלי סגירה מסודרת —
  /// הכרטיסיות שבהם פתוחות מבחינת המשתמש. מחזיר את מספר הכרטיסיות.
  ///
  /// ⚠️ רץ פעם אחת בהפעלה קרה, לפני שה-blocs נבנים: `TabsBloc`
  /// ו-`NavigationBloc` טוענים שניהם אחריו ורואים אותו דבר.
  static Future<int> adoptOrphanWindowSessions() async {
    final host = WindowTabsSession.current.slot;
    if (host == null) return 0;
    try {
      final adopted = await _staticStore.adoptInto(host);
      if (adopted > 0) {
        debugPrint('אומצו $adopted כרטיסיות מחלונות שנסגרו בלי סגירה מסודרת');
      }
      return adopted;
    } catch (e) {
      debugPrint('⚠️ adoptOrphanWindowSessions failed: $e');
      return 0;
    }
  }

  /// המשבצת הגבוהה ביותר שחלון יכול לתפוס: תקרת חלונות ה-Dart.
  static const int maxWindowSlot = ViewWindowRegistry.maxWindows;

  /// החלופה ל-[adoptOrphanWindowSessions] כש"שחזר את כל החלונות" דלוק:
  /// הסשנים נשארים נפרדים, במשבצות רצופות אחרי המארח, כדי שכל חלון חדש —
  /// שתופס את המשבצת הפנויה הראשונה — ימצא במשבצת שלו את הסשן שנועד לו.
  /// מחזיר את המשבצות שיש לפתוח להן חלון, לפי הסדר.
  static Future<List<int>> compactWindowSessions() async {
    final host = WindowTabsSession.current.slot;
    if (host == null) return const [];
    try {
      return await _staticStore.compactAround(host, maxWindowSlot);
    } catch (e) {
      debugPrint('⚠️ compactWindowSessions failed: $e');
      return const [];
    }
  }

  /// שומר רק את אינדקס הטאב הנוכחי, בלי לקודד מחדש את כל הטאבים.
  ///
  /// מיועד למעבר בין טאבים, שבו רשימת הטאבים עצמה לא משתנה. הכתיבה
  /// מושהית ב-[_indexDebounce]: מעבר מהיר בין כרטיסיות מתמזג לכתיבה אחת.
  /// [flushPendingWrites] מוציא כתיבה ממתינה מיד.
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {
    final slot = _sessionSlot;
    if (slot == null) return;
    final persistedIndexByOriginalIndex = <int, int>{};
    for (var i = 0; i < tabs.length; i++) {
      persistedIndexByOriginalIndex[i] = i;
    }
    window._pendingIndex = _resolvePersistedCurrentTabIndex(
      persistedIndexByOriginalIndex,
      currentTabIndex,
      tabs.length,
    );
    window._pendingIndexSlot = slot;
    window._indexTimer?.cancel();
    window._indexTimer = Timer(
      _indexDebounce,
      () => unawaited(flushPendingWrites()),
    );
  }

  /// מוציא כתיבה מושהית של האינדקס הפעיל מיד. נקרא לפני סגירת החלון.
  Future<void> flushPendingWrites() async {
    final index = window._pendingIndex;
    final slot = window._pendingIndexSlot;
    window._cancelPendingIndex();
    if (index == null || slot == null) return;
    await _store.saveCurrentIndex(slot, index);
  }
}

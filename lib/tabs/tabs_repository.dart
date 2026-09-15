import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';
import 'package:flutter/foundation.dart';

class TabsRepository {
  TabsRepository({this.sessions});

  /// שם ה-box ההיסטורי. נשאר ככינוי שהגיבוי משתמש בו בשמות הסעיפים.
  static const String boxName = 'tabs';

  /// השהיית הכתיבה של האינדקס הפעיל. זו הפעולה השכיחה ביותר, וכתיבת
  /// SQLite סינכרונית על ה-UI — מעבר מהיר בין כרטיסיות מתמזג לכתיבה אחת.
  static const Duration _indexDebounce = Duration(milliseconds: 300);

  /// מאגר הסשנים שכל המופעים ייפלו אליו; לבדיקות בלבד.
  @visibleForTesting
  static WindowSessionStore? debugSessions;

  /// מאגר הסשנים של המופע הזה; null = המאגר הגלובלי.
  final WindowSessionStore? sessions;

  WindowSessionStore get _store =>
      sessions ?? debugSessions ?? WindowSessionStore.instance;

  static WindowSessionStore get _staticStore =>
      debugSessions ?? WindowSessionStore.instance;

  /// המשבצת שהחלון הזה כותב אליה, או null כשאינו יכול לשמור.
  ///
  /// ⚠️ חלון בלי משבצת אינו שומר, ובשום מצב אינו נופל למשבצת של חלון אחר
  /// — זו הייתה דריסת הכרטיסיות שלו.
  static int? get _sessionSlot => UserStateSlot.current;

  /// המשבצת של החלון הראשון בתהליך — הסשן שנטען בהפעלה קרה.
  static const int _hostSlot = UserStateSlot.single;

  /// דור הסשן של החלון הזה: עולה בכל [importRaw]. `TabsBloc` שנבנה לפני
  /// הייבוא אינו שומר יותר — אחרת סגירתו בעת ההפעלה מחדש הייתה כותבת את
  /// הכרטיסיות שבזיכרונו על אלה ששוחזרו.
  static int get sessionGeneration => _sessionGeneration;
  static int _sessionGeneration = 0;

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
    _cancelPendingIndex();
    await _store.save(
      slot,
      tabsJson: jsonEncode(tabs is List ? tabs : <dynamic>[]),
      currentIndex: current is int ? current : 0,
    );
    _sessionGeneration++;
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

  /// ממפה נתיבי קבצים שמורים של טאבים מתיקיית הספרייה הישנה [fromDir] לחדשה
  /// [toDir], כדי שספרי PDF/DOCX פתוחים ייטענו מהמיקום החדש לאחר רענון התוכנה.
  /// משכתב את שדות 'path' ו-'filePath' בכל עומק (כולל ה-book המקונן).
  Future<void> remapBookPaths(String fromDir, String toDir) async {
    // ⚠️ הסשן של החלון הראשון, גם כשההעברה מופעלת מחלון משני: העברת
    // הספרייה היא פעולה של התוכנה, וזה הסשן שנטען בהפעלה קרה.
    final session = await _store.load(_hostSlot);
    if (session == null) return;
    var changed = false;
    final remapped = _decodeTabs(
      session.tabsJson,
    ).map((e) => _remapNode(e, fromDir, toDir, () => changed = true)).toList();
    if (!changed) return;
    await _store.save(
      _hostSlot,
      tabsJson: jsonEncode(remapped),
      currentIndex: session.currentIndex,
    );
  }

  /// ממפה נתיבי קבצים של טאבים פתוחים *בזיכרון* מ-[fromDir] ל-[toDir].
  /// טאב שהנתיב שלו לא משתנה מוחזר כאובייקט המקורי (ללא בנייה מחדש);
  /// טאב ששונה נבנה מחדש דרך toJson→fromJson עם הנתיב החדש.
  /// נדרש בנוסף ל-[remapBookPaths]: שמירה למסד בלבד נדרסת ע"י שמירת
  /// הטאבים שבזיכרון בעת dispose, ולכן ספר PDF היה נטען מהנתיב הישן.
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
  /// ⚠️ סינכרוני — נקרא מבנאי של bloc. מחייב שהמסד כבר נפתח באתחול.
  List<OpenedTab> loadTabs() {
    final slot = _sessionSlot;
    if (slot == null) return const [];
    try {
      final session = _store.loadOpened(slot);
      if (session == null) return const [];
      final tabs = <OpenedTab>[];
      for (final e in _decodeTabs(session.tabsJson)) {
        try {
          tabs.add(OpenedTab.fromJson(castMap(e)));
        } catch (tabError) {
          debugPrint('⚠️ Skipping tab that failed to restore: $tabError');
        }
      }
      return tabs;
    } catch (e) {
      debugPrint('⚠️ Error loading tabs from disk: $e');
      return [];
    }
  }

  int loadCurrentTabIndex() {
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
    _cancelPendingIndex();
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
      _cancelPendingIndex();
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
    if (WindowRole.isSecondary || WindowBus.instance.hasOtherWindows) return 0;
    final host = _sessionSlot;
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

  /// החלופה ל-[adoptOrphanWindowSessions] כש"שחזר את כל החלונות" דלוק:
  /// הסשנים נשארים נפרדים, במשבצות רצופות אחרי המארח, כדי שכל חלון חדש —
  /// שתופס את המשבצת הפנויה הראשונה — ימצא במשבצת שלו את הסשן שנועד לו.
  /// מחזיר את המשבצות שיש לפתוח להן חלון, לפי הסדר.
  static Future<List<int>> compactWindowSessions() async {
    if (WindowRole.isSecondary || WindowBus.instance.hasOtherWindows) {
      return const [];
    }
    final host = _sessionSlot;
    if (host == null) return const [];
    try {
      return await _staticStore.compactAround(host, WindowBus.slotCount);
    } catch (e) {
      debugPrint('⚠️ compactWindowSessions failed: $e');
      return const [];
    }
  }

  /// האינדקס הפעיל שממתין לכתיבה, והמשבצת שאליה.
  static Timer? _indexTimer;
  static int? _pendingIndex;
  static int? _pendingIndexSlot;

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
    _pendingIndex = _resolvePersistedCurrentTabIndex(
      persistedIndexByOriginalIndex,
      currentTabIndex,
      tabs.length,
    );
    _pendingIndexSlot = slot;
    _indexTimer?.cancel();
    _indexTimer = Timer(_indexDebounce, () => unawaited(flushPendingWrites()));
  }

  /// מוציא כתיבה מושהית של האינדקס הפעיל מיד. נקרא לפני סגירת החלון.
  Future<void> flushPendingWrites() async {
    _indexTimer?.cancel();
    _indexTimer = null;
    final index = _pendingIndex;
    final slot = _pendingIndexSlot;
    _pendingIndex = null;
    _pendingIndexSlot = null;
    if (index == null || slot == null) return;
    await _store.saveCurrentIndex(slot, index);
  }

  static void _cancelPendingIndex() {
    _indexTimer?.cancel();
    _indexTimer = null;
    _pendingIndex = null;
    _pendingIndexSlot = null;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// מחבר את [WindowBus] לחלון שהוא יושב בו.
///
/// תופס משבצת באפיק, עונה על בקשות מחלונות אחרים, ומשחרר בסגירה. חייב
/// לשבת **מתחת** ל-`TabsBloc` ול-`NavigationBloc` — שתי הבקשות הנתמכות
/// זקוקות להם.
///
/// ⚠️ השחרור ב-`dispose` אינו נימוס: משבצת שלא שוחררה נשארת רשומה בלי
/// מאזין, וחלון חדש לא יוכל לתפוס אותה. `WindowBus.peers` אמנם מסנן
/// משבצות מתות לפי timeout, אבל זה עולה המתנה בכל פתיחת תפריט.
class WindowBusHost extends StatefulWidget {
  const WindowBusHost({super.key, required this.child});

  final Widget child;

  @override
  State<WindowBusHost> createState() => _WindowBusHostState();
}

class _WindowBusHostState extends State<WindowBusHost> {
  Timer? _peerRefresh;

  @override
  void initState() {
    super.initState();
    // ⚠️ כל השכבה הזו מגודרת בפלטפורמה. בלי הגידור מובייל שילם
    // `Timer.periodic` של שלוש שניות, `ReceivePort` פתוח ושלוש שאילתות
    // אפיק בכל פעימה — בשביל יכולת שאינה קיימת שם בכלל.
    if (!MultiWindowService.canOpenWindows) return;

    // ⚠️ החלון הראשון רושם גם את כינוי הבעלים. בלעדיו איתור מחזיק המאגרים
    // המשותפים היה סריקת `describe` עם timeout — והבעלים דווקא עסוק בזמן
    // שנפתח חלון שני, כלומר הסריקה פקעה בדיוק כשהיא נחוצה.
    final slot = WindowBus.instance.register(asOwner: !WindowRole.isSecondary);
    WindowBus.instance.onRequest = _handleRequest;
    // ה-runner צריך את המיפוי כדי לתרגם "החלון שתחת הסמן" למשבצת בגרירה.
    if (slot != null) {
      unawaited(const MultiWindowService().setBusSlot(slot));
    }

    // ⚠️ רענון ברקע ולא לפי דרישה: בניית תפריט ההקשר סינכרונית ואינה
    // יכולה להמתין לסריקה. בלי זה הלחיצה הימנית הראשונה אחרי פתיחת חלון
    // הייתה מציגה תת-תפריט ריק.
    //
    // הפעימה מופסקת כשאין עוד חלון אחר: הבדיקה סינכרונית וזולה
    // ([WindowBus.hasOtherWindows]), והמקרה השכיח הוא חלון יחיד.
    unawaited(_refreshPeers());
    _peerRefresh = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshPeers()),
    );

    // ה-runner קורא לכאן כשהוא מחזיר חלון מוסתר לשימוש עם כרטיסיה חדשה.
    MultiWindowService.channel.setMethodCallHandler((call) async {
      if (call.method == 'adoptPayload' && call.arguments is String) {
        await _adoptPayload(call.arguments as String);
      }
      return null;
    });

    // ⚠️ הגדרה שהשתנתה בחלון אחר כבר נכתבה ל-box המקומי, אבל ה-state
    // שנגזר ממנה עוד לא. בלי הטעינה מחדש המשתמש היה מחליף ערכת נושא
    // בחלון אחד ורואה שני חלונות של אותה תוכנה נראים שונה.
    _settingsChanged = SettingsSync.instance.changes.listen((_) {
      if (mounted) context.read<SettingsBloc>().add(LoadSettings());
    });
  }

  StreamSubscription<String>? _settingsChanged;

  /// קולט מטען שנשלח לחלון שהוחזר לשימוש.
  ///
  /// ⚠️ חלון סגור מוסתר ולא נהרס, ולכן הוא נפתח שוב עם הכרטיסיות הישנות
  /// שלו. הן נסגרות כאן: המשתמש גרר כרטיסיה אחת החוצה וזה מה שהוא מצפה
  /// לראות, לא שרידים מחלון שסגר קודם.
  ///
  /// ⚠️ **ההחלפה היא אירוע אחד ([AdoptTab]) ולא `CloseAllTabs` ואחריו
  /// `AddTab`.** הצמד העביר את המצב דרך אפס כרטיסיות, ו-`ReadingScreen`
  /// מנווט למסך הספרייה בדיוק במעבר הזה — כלומר כל חלון שכבר היה פתוח
  /// ונסגר נחת בספרייה במקום על הכרטיסיה שנגררה אליו.
  Future<void> _adoptPayload(String payload) async {
    final tab = MultiWindowService.decodePayload(payload);
    if (tab == null) {
      // ⚠️ המקור כבר מחק את הכרטיסיה על סמך `openWindow` שהחזיר true. כשל
      // שקט כאן פירושו כרטיסיה שנעלמה בלי שום סימן.
      if (MultiWindowService.payloadHasTab(payload)) {
        UiSnack.showError(WindowMessages.transferredTabDecodeFailed);
        try {
          ErrorLogFile.append(
            title: 'פענוח כרטיסיה שהועברה לחלון שהוחזר לשימוש נכשל',
            error: 'decodePayload returned null for a payload with a tab',
            stackTrace: StackTrace.current,
          );
        } catch (_) {
          // רישום הוא best-effort ולעולם אינו חוסם את החזרת החלון.
        }
      }
      return;
    }
    if (!mounted) return;
    context.read<TabsBloc>().add(AdoptTab(tab));
    context.read<NavigationBloc>().add(
      const NavigateToScreen(Screen.reading),
    );
  }

  Future<void> _refreshPeers() async {
    // חלון יחיד: אין את מי לשאול, ואין טעם לצאת לנייטיב בשביל `visibleSlots`.
    if (!WindowBus.instance.hasOtherWindows) {
      if (MultiWindowService.knownPeers.isNotEmpty) {
        MultiWindowService.publishKnownPeers(const []);
      }
      return;
    }
    final peers = await const MultiWindowService().otherWindows();
    if (!mounted) return;
    MultiWindowService.publishKnownPeers(peers);
  }

  @override
  void dispose() {
    _peerRefresh?.cancel();
    unawaited(_settingsChanged?.cancel());
    SettingsSync.instance.dispose();
    // ⚠️ המשבצת, ה-`onRequest` ומטפל הערוץ **אינם** משוחררים כאן: ב-
    // `RestartWidget` ה-`initState` החדש רץ לפני ה-`dispose` הזה, ושחרור
    // כאן היה מוחק את הרישום שהוא בדיוק עשה.
    MultiWindowService.publishKnownPeers(const []);
    super.dispose();
  }

  Future<Object?> _handleRequest(Map<String, dynamic> request) async {
    switch (request['type']) {
      case MultiWindowService.requestDescribe:
        return _describe();
      case MultiWindowService.requestReceiveTab:
        return _receiveTab(request['tab'], request['index']);
      case MultiWindowService.requestDragOver:
        return _dragOver(request);
      case MultiWindowService.requestOpenUri:
        return _openUri(request['uri']);
      case MultiWindowService.requestIndex:
        return _runIndexRequest(request['op']);
      case MultiWindowService.requestDragLeave:
        externalTabDrag.value = null;
        return true;
      case UserStateListStore.requestChanged:
        return UserStateListStore.instance.handleRequest(request);
      case SettingsSync.requestChanged:
        // הגדרה שונתה בחלון אחר — מוחלת על ה-box המקומי ומרעננת את ה-state.
        return SettingsSync.instance.handleRequest(request);
      case MultiWindowService.requestRestart:
        return _restartSelf();
      default:
        return null;
    }
  }

  /// חלון אחר שחזר גיבוי או ייבא נתונים: העץ נבנה מחדש כדי לטעון אותם.
  ///
  /// ⚠️ חלון מוסתר (שנסגר ומחכה ל-Ctrl+Shift+T) אינו נבנה מחדש: סגירת
  /// ה-`TabsBloc` שלו הייתה כותבת מחדש את הסשן שהמשתמש מחק בסגירה.
  Future<bool> _restartSelf() async {
    if (!mounted) return false;
    if (!await AppWindowScope.controllerOf(context).isVisible()) return false;
    if (!mounted) return false;
    await resetRuntimeStateForAppRestart();
    if (!mounted) return false;
    RestartWidget.restartApp(
      context,
      afterRestart: WebViewEnvironmentHolder.disposeForAppRestart,
    );
    return true;
  }

  /// בקשת אינדוקס מחלון משני. רק המארח מבצע — Tantivy נועל את ה-writer
  /// בלעדית, והנעילה שלו.
  ///
  /// מחזיר true רק אחרי שהאירוע נשלח בפועל, כי השולח מדווח למשתמש לפיו.
  bool _runIndexRequest(Object? op) {
    if (!mounted || WindowRole.isSecondary) return false;
    final indexing = context.read<IndexingBloc>();
    switch (op) {
      case MultiWindowService.indexOpAll:
        final library = context.read<LibraryBloc>().state.library;
        if (library == null) return false;
        indexing.add(StartIndexing(library));
        return true;
      case MultiWindowService.indexOpClear:
        indexing.add(ClearIndex());
        return true;
      default:
        return false;
    }
  }

  /// קישור `otzaria://` שהמארח ניקז והפנה לכאן, כי זה החלון הפעיל האחרון.
  ///
  /// האישור חוזר מיד, לפני הטיפול: פתיחת ספר עלולה להימשך יותר מפקיעת הזמן
  /// של המארח, והוא היה פותח את הקישור גם אצלו.
  Future<Object?> _openUri(Object? uri) async {
    if (uri is! String || uri.trim().isEmpty) return false;
    final screen = mainWindowScreenKey.currentState;
    if (screen == null) return false;
    unawaited(screen.handleInternalDeepLink(uri));
    return true;
  }

  /// כרטיסיה מחלון אחר נגררת מעל החלון הזה.
  ///
  /// מחזיר את מיקום ההכנסה שחושב ברצועת הכרטיסיות, או null כשהסמן אינו
  /// מעליה — כך המקור יודע אם השחרור ימזג למקום מדויק או רק יעביר לסוף.
  Future<Object?> _dragOver(Map<String, dynamic> request) async {
    final x = request['x'];
    final y = request['y'];
    if (x is! int || y is! int || !mounted) return null;
    final local = await const MultiWindowService().screenToClient(
      x,
      y,
      View.of(context).devicePixelRatio,
    );
    if (local == null || !mounted) return null;
    externalTabDrag.value = ExternalTabDrag(
      title: (request['title'] as String?) ?? '',
      local: local,
    );
    // הרצועה מחשבת את מיקום ההכנסה בתגובה לעדכון, ולכן הערך נקרא אחריו.
    return externalTabDropIndex.value;
  }

  /// תיאור לתצוגה בתת-תפריט של חלון אחר.
  Map<String, Object?> _describe() {
    final state = context.read<TabsBloc>().state;
    final current = state.currentTab;
    return {
      'title': current?.title ?? 'חלון ריק',
      'tabCount': state.tabs.length,
      // מאפשר לחלונות משניים לאתר את הבעלים של המאגרים המשותפים.
      'isOwner': !WindowRole.isSecondary,
      'activeWorkspaceId': context
          .read<WorkspaceBloc>()
          .state
          .activeWorkspaceId,
    };
  }

  /// קולט כרטיסיה שנשלחה מחלון אחר.
  ///
  /// מחזיר true רק אחרי שהכרטיסיה **פוענחה בהצלחה** ונוספה. השולח מסיר
  /// אותה מעצמו רק על סמך התשובה הזו, ולכן כישלון כאן חייב להיות false
  /// ולא חריגה — אחרת הכרטיסיה נעלמת משני הצדדים.
  bool _receiveTab(Object? tabJson, Object? index) {
    if (tabJson is! Map) return false;
    final OpenedTab tab;
    try {
      tab = OpenedTab.fromJson(Map<String, dynamic>.from(tabJson));
    } catch (e) {
      debugPrint('WindowBusHost: failed to decode incoming tab: $e');
      return false;
    }
    if (!mounted) return false;
    // החיווי נעלם ברגע שהכרטיסיה התקבלה, ולא בטיימר של השולח.
    externalTabDrag.value = null;
    final tabsBloc = context.read<TabsBloc>();
    tabsBloc.add(AddTab(tab));
    // שוחררה על רצועת הכרטיסיות — נכנסת למקום המדויק ולא לסוף.
    if (index is int) {
      tabsBloc.add(MoveTab(tab, index));
    }
    context.read<NavigationBloc>().add(
      const NavigateToScreen(Screen.reading),
    );
    // הכרטיסיה עברה לכאן — והמשתמש מצפה לעבור איתה. בלי זה הפוקוס נשאר
    // בחלון המקור, והכרטיסיה "נעלמת" אל חלון שמאחור.
    unawaited(const MultiWindowService().raiseSelf());
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

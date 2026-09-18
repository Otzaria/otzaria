import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// עטיפה דקה ל-Win32 עבור אוטומציית פרויקט השו"ת.
///
/// כל קריאה כאן היא קריאה **חוצת-תהליכים** אל `RESPONSA.exe`. שלוש
/// מלכודות מאומתות מקובעות במודול, כדי שלא יחזרו:
///
/// 1. `GetWindowText` אינו עובד חוצה-תהליכים על פקדי ילד — חובה
///    `WM_GETTEXTLENGTH` + `WM_GETTEXT`.
/// 2. `WM_CLOSE` על חלון של האפליקציה **מפיל אותה**. המודול אינו חושף
///    אותו כלל; חלון MDI נסגר ב-`WM_MDIDESTROY`, שהוא ההודעה התקנית.
/// 3. **כל שליחה סינכרונית עוברת `SendMessageTimeout`.** `SendMessage`
///    רגיל חוזר רק כשהתהליך היעד מעבד את ההודעה, וכשמודאל פתוח הוא אינו
///    חוזר לעולם — גם timeout ברמת הפעולה לא מציל, כי השרשור עצמו תקוע.
///
/// **חובה להריץ באיזולט רקע.** הקריאות סינכרוניות וחוסמות; על Windows
/// ה-UI isolate רץ על ה-platform thread, וקריאה חוסמת שם מקפיאה כל פריים.
class ResponsaWin32 {
  ResponsaWin32._();

  // --- הודעות
  static const int wmCommand = 0x0111;
  static const int wmGetText = 0x000D;
  static const int wmGetTextLength = 0x000E;
  static const int wmSetText = 0x000C;
  static const int wmMdiGetActive = 0x0229;
  static const int wmMdiDestroy = 0x0221;

  static const int bmClick = 0x00F5;

  static const int lbGetCount = 0x018B;
  static const int lbGetText = 0x0189;
  static const int lbGetTextLen = 0x018A;
  static const int lbSetSel = 0x0185;
  static const int lbnSelChange = 1;

  static const int tcmSetCurFocus = 0x1330;

  /// תקרת זמן לשליחה סינכרונית בודדת.
  static const int defaultSendTimeoutMs = 15000;

  /// תקרה קצרה לקריאות סריקה (כותרת, ספירה). חלון חונה שאינו מגיב עולה
  /// את מלוא התקרה, ואסור שחלון אחד יעצור מיפוי שלם.
  static const int scanTimeoutMs = 2000;

  static const int _smtoAbortIfHung = 0x0002;

  static final _getDlgCtrlId = DynamicLibrary.open('user32.dll')
      .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
        'GetDlgCtrlID',
      );

  // ------------------------------------------------------------ שליחה

  /// שליחה סינכרונית עם תקרת זמן. `null` כשהיעד לא ענה.
  static int? send(
    int hwnd,
    int message, {
    int wParam = 0,
    int lParam = 0,
    int timeoutMs = defaultSendTimeoutMs,
  }) {
    final result = calloc<IntPtr>();
    try {
      final ok = SendMessageTimeout(
        HWND(Pointer.fromAddress(hwnd)),
        message,
        WPARAM(wParam),
        LPARAM(lParam),
        SEND_MESSAGE_TIMEOUT_FLAGS(_smtoAbortIfHung),
        timeoutMs,
        result,
      );
      return ok.value == 0 ? null : result.value;
    } finally {
      calloc.free(result);
    }
  }

  /// פקודת תפריט. `Post` ולא `Send` — פקודה שפותחת מודאל לא תחזיר שליטה
  /// עד שהמודאל ייסגר.
  static void postCommand(int hwnd, int commandId) {
    PostMessage(
      HWND(Pointer.fromAddress(hwnd)),
      wmCommand,
      WPARAM(commandId),
      const LPARAM(0),
    );
  }

  /// לחיצה על כפתור. `false` כשהיעד לא ענה בזמן.
  static bool click(int hwnd, {int timeoutMs = defaultSendTimeoutMs}) =>
      send(hwnd, bmClick, timeoutMs: timeoutMs) != null;

  // ------------------------------------------------------------- טקסט

  static String className(int hwnd) {
    final buffer = wsalloc(256);
    try {
      GetClassName(HWND(Pointer.fromAddress(hwnd)), buffer, 256);
      return buffer.toDartString();
    } finally {
      free(buffer);
    }
  }

  /// טקסט של חלון או פקד — עובד גם חוצה-תהליכים.
  static String windowText(int hwnd, {int timeoutMs = scanTimeoutMs}) {
    final length = send(hwnd, wmGetTextLength, timeoutMs: timeoutMs) ?? 0;
    if (length <= 0) return '';
    final buffer = wsalloc(length + 1);
    try {
      send(
        hwnd,
        wmGetText,
        wParam: length + 1,
        lParam: buffer.address,
        timeoutMs: timeoutMs,
      );
      return buffer.toDartString();
    } finally {
      free(buffer);
    }
  }

  static void setWindowText(int hwnd, String text) {
    final buffer = text.toNativeUtf16();
    try {
      send(hwnd, wmSetText, lParam: buffer.address);
    } finally {
      free(buffer);
    }
  }

  // ------------------------------------------------------------ מיפוי

  static int controlId(int hwnd) => _getDlgCtrlId(Pointer.fromAddress(hwnd));

  static bool isVisible(int hwnd) =>
      IsWindowVisible(HWND(Pointer.fromAddress(hwnd)));

  static bool isWindow(int hwnd) => IsWindow(HWND(Pointer.fromAddress(hwnd)));

  /// `GA_ROOT` — חלון עליון אמיתי ולא ילד שמתחזה.
  static bool isTopLevel(int hwnd) =>
      GetAncestor(
        HWND(Pointer.fromAddress(hwnd)),
        const GET_ANCESTOR_FLAGS(2),
      ).address ==
      hwnd;

  static int processOf(int hwnd) {
    final pid = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(HWND(Pointer.fromAddress(hwnd)), pid);
      return pid.value;
    } finally {
      calloc.free(pid);
    }
  }

  /// כל חלונות העל של תהליך.
  static List<int> topWindows(int pid) =>
      _enumTop().where((hwnd) => processOf(hwnd) == pid).toList();

  /// כל חלונות העל בכל התהליכים ממחלקה נתונה, כזוגות `(hwnd, pid)`.
  static List<({int hwnd, int pid})> topWindowsByClass(String wanted) => [
    for (final hwnd in _enumTop())
      if (className(hwnd) == wanted) (hwnd: hwnd, pid: processOf(hwnd)),
  ];

  /// כל הצאצאים (רקורסיבי).
  static List<int> children(int hwnd) {
    final found = <int>[];
    final callback = NativeCallable<WNDENUMPROC>.isolateLocal((
      Pointer child,
      int _,
    ) {
      found.add(child.address);
      return TRUE;
    }, exceptionalReturn: FALSE);
    try {
      EnumChildWindows(
        HWND(Pointer.fromAddress(hwnd)),
        callback.nativeFunction,
        const LPARAM(0),
      );
    } finally {
      callback.close();
    }
    return found;
  }

  /// רק הילדים הישירים, בסדר ה-Z — מהוותיק לחדש.
  static List<int> directChildren(int hwnd) {
    final found = <int>[];
    var child = GetWindow(
      HWND(Pointer.fromAddress(hwnd)),
      const GET_WINDOW_CMD(5), // GW_CHILD
    ).value;
    while (child.address != 0) {
      found.add(child.address);
      child = GetWindow(child, const GET_WINDOW_CMD(2)).value; // GW_HWNDNEXT
    }
    return found;
  }

  static List<int> _enumTop() {
    final found = <int>[];
    final callback = NativeCallable<WNDENUMPROC>.isolateLocal((
      Pointer hwnd,
      int _,
    ) {
      found.add(hwnd.address);
      return TRUE;
    }, exceptionalReturn: FALSE);
    try {
      EnumWindows(callback.nativeFunction, const LPARAM(0));
    } finally {
      callback.close();
    }
    return found;
  }

  // ---------------------------------------------------------- ListBox

  /// `-1` כשהרשימה לא ענתה. **אינו** שווה ל-0: הפרש בין "ריקה" ל"לא
  /// ידוע" הוא בדיוק ההבדל שמייצר ספירה שקרית.
  static int listBoxCount(int hwnd) =>
      send(hwnd, lbGetCount, timeoutMs: 3000) ?? -1;

  static String listBoxItem(int hwnd, int index) {
    final length =
        send(hwnd, lbGetTextLen, wParam: index, timeoutMs: 3000) ?? 0;
    if (length <= 0) return '';
    final buffer = wsalloc(length + 2);
    try {
      send(
        hwnd,
        lbGetText,
        wParam: index,
        lParam: buffer.address,
        timeoutMs: 3000,
      );
      return buffer.toDartString();
    } finally {
      free(buffer);
    }
  }

  static List<String> listBoxItems(int hwnd, {int? limit}) {
    final count = listBoxCount(hwnd);
    if (count <= 0) return const [];
    final take = limit == null || limit > count ? count : limit;
    return [for (var i = 0; i < take; i++) listBoxItem(hwnd, i)];
  }

  /// בחירת פריט ברשימת התוצאות והודעה להורה.
  ///
  /// הרשימה היא Multi-Select, ולכן `LB_SETCURSEL` מחזיר `-1` תמיד. בלי
  /// הודעת `LBN_SELCHANGE` ידנית האפליקציה אינה יודעת שהבחירה השתנתה.
  static void listBoxSelect(int parent, int listBox, int index) {
    send(listBox, lbSetSel, wParam: 1, lParam: index);
    final notify = (lbnSelChange << 16) | (controlId(listBox) & 0xFFFF);
    send(parent, wmCommand, wParam: notify, lParam: listBox);
  }

  static void setTabFocus(int tabControl, int index) {
    send(tabControl, tcmSetCurFocus, wParam: index);
  }

  // -------------------------------------------------------------- MDI

  /// נתיב קובץ ההרצה של תהליך.
  ///
  /// `QueryFullProcessImageName` ולא הרצת `powershell`: זו קריאה אחת
  /// במקום יצירת תהליך, והיא נקראת פעם אחת לכל מופע בכל פתיחת ספר.
  /// יצירת תהליך בלולאה היא בדיוק מה שהופך פעולה של שנייה לפעולה של
  /// שבע במכונה עמוסה.
  static String? processImagePath(int pid) {
    final handle = OpenProcess(
      const PROCESS_ACCESS_RIGHTS(0x1000), // PROCESS_QUERY_LIMITED_INFORMATION
      false,
      pid,
    ).value;
    if (handle.address == 0) return null;
    final size = calloc<Uint32>()..value = 1024;
    final buffer = wsalloc(1024);
    try {
      final ok = QueryFullProcessImageName(
        handle,
        const PROCESS_NAME_FORMAT(0),
        buffer,
        size,
      );
      return ok.value ? buffer.toDartString() : null;
    } finally {
      calloc.free(size);
      free(buffer);
      CloseHandle(handle);
    }
  }

  static int? mdiClient(int mainWindow) {
    for (final child in children(mainWindow)) {
      if (className(child) == 'MDIClient') return child;
    }
    return null;
  }

  static List<String> mdiTitles(int mainWindow) {
    final client = mdiClient(mainWindow);
    if (client == null) return const [];
    return [for (final child in directChildren(client)) windowText(child)];
  }

  static String? mdiActiveTitle(int mainWindow) {
    final client = mdiClient(mainWindow);
    if (client == null) return null;
    final active = send(client, wmMdiGetActive, timeoutMs: 3000) ?? 0;
    return active == 0 ? null : windowText(active);
  }

  /// סוגר חלון MDI בודד.
  ///
  /// `WM_MDIDESTROY` היא ההודעה התקנית של MDI ונשלחת ל-`MDIClient`.
  /// **אין** להחליף אותה ב-`WM_CLOSE` על חלון של האפליקציה — זה הפיל את
  /// המופע פעמיים במדידות.
  static bool destroyMdiChild(int mainWindow, int child) {
    final client = mdiClient(mainWindow);
    if (client == null) return false;
    send(client, wmMdiDestroy, wParam: child, timeoutMs: 8000);
    return true;
  }

  // -------------------------------------------------------- הבאה לחזית

  static const int _swRestore = 9;
  static const int _swShow = 5;

  /// מביא חלון לחזית, ומשחזר אותו אם הוא ממוזער.
  ///
  /// שלושת הצעדים נחוצים ואינם חופפים: חלון ממוזער לא ייראה גם אם יעבור
  /// לחזית, `SetForegroundWindow` הוא זה שמעביר את הפוקוס בין תהליכים,
  /// ו-`BringWindowToTop` מסדר את ה-Z-order כשהפוקוס כבר שם.
  ///
  /// Windows מתיר החלפת חזית רק לתהליך שהוא עצמו בחזית. מכאן שהקריאה
  /// חייבת לצאת בזמן שאוצריא פעילה — כלומר מיד בתום הפתיחה, ולא מאוחר
  /// יותר. כשלון אינו משמעותי: הספר נפתח, רק החלון לא קפץ.
  static void bringToFront(int hwnd) {
    final handle = HWND(Pointer.fromAddress(hwnd));
    if (IsIconic(handle)) {
      ShowWindow(handle, SHOW_WINDOW_CMD(_swRestore));
    } else {
      ShowWindow(handle, SHOW_WINDOW_CMD(_swShow));
    }
    SetForegroundWindow(handle);
    BringWindowToTop(handle);
  }
}

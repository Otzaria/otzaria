import 'dart:ffi';
import 'package:flutter/foundation.dart';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

/// צומת אחד בעץ הקטלוג של פרויקט השו"ת.
class ResponsaTreeNode {
  final String name;
  final int param;
  final int level;

  /// הנתיב המלא מהשורש, כולל שם הצומת עצמו.
  final String path;

  /// כמה ילדים יש לצומת לפי ה-TreeView. `0` = עלה.
  final int childCount;

  const ResponsaTreeNode({
    required this.name,
    required this.param,
    required this.level,
    required this.path,
    required this.childCount,
  });
}

/// הסריקה לא הושלמה ולכן אסור שתחליף קטלוג קיים. ההודעה מוצגת למשתמש כמות שהיא.
class ResponsaTreeReadException implements Exception {
  final String message;

  const ResponsaTreeReadException(this.message);

  @override
  String toString() => message;
}

/// המקור היחיד לרשימת הספרים (אין בהתקנה קובץ קריא שמכיל אותה). העץ נטען
/// עצלנית, ו-`RESPONSA.exe` הוא 32-ביט - ראה [_TreeSession.itemSize32].
class ResponsaTreeReader {
  ResponsaTreeReader._();

  static const int tvFirst = 0x1100;
  static const int tvmExpand = tvFirst + 2;
  static const int tvmGetNextItem = tvFirst + 10;
  static const int tvmGetItemW = tvFirst + 62;

  static const int tvgnRoot = 0x0000;
  static const int tvgnNext = 0x0001;
  static const int tvgnChild = 0x0004;

  static const int tveCollapse = 0x0001;
  static const int tveExpand = 0x0002;
  static const int tveCollapseReset = 0x8000;

  static const String pathSeparator = ' > ';

  /// זורק כשהודעה לא נענתה: היא נראית כמו "אין עוד ילדים", וסריקה קטועה
  /// הייתה נשמרת כקטלוג שלם ושוברת סימניות. ביטול אינו כשל.
  static List<ResponsaTreeNode> walk({
    required int pid,
    required int treeHandle,
    void Function(int scanned)? onProgress,
    void Function(int done, int total)? onSection,
    bool Function()? shouldStop,
    int progressEvery = 500,
    int maxNodes = 3000000,
  }) {
    final session = _TreeSession.open(pid, treeHandle);
    if (session == null) {
      throw const ResponsaTreeReadException(
        'אין גישה לחלון של בר אילן. ייתכן שהוא פועל כמנהל מערכת ואוצריא לא '
        '— יש לפתוח את שניהם באותה הרשאה.',
      );
    }
    final walk = _Walk(
      session: session,
      onProgress: onProgress,
      shouldStop: shouldStop,
      progressEvery: progressEvery,
      maxNodes: maxNodes,
    );
    try {
      final sections = [
        for (
          var item = session.root;
          item != 0;
          item = session.nextSibling(item)
        )
          item,
      ];
      onSection?.call(0, sections.length);
      for (var i = 0; i < sections.length; i++) {
        if (!walk.visit(sections[i], 0, const <String>[])) break;
        onSection?.call(i + 1, sections.length);
      }
    } finally {
      session.close();
    }
    if (session.failed) {
      throw const ResponsaTreeReadException(
        'בר אילן הפסיק להגיב באמצע הסריקה, או שנסגר. הקטלוג הקיים לא הוחלף '
        '— יש לנסות שוב.',
      );
    }
    return walk.nodes;
  }

  /// מאתר את ה-TreeView של הקטלוג בתוך דיאלוג העיון.
  static int? findCatalogTree(int dialogHandle) {
    for (final child in ResponsaWin32.children(dialogHandle)) {
      if (ResponsaWin32.className(child) == 'SysTreeView32') return child;
    }
    return null;
  }
}

/// החוצץ בתהליך היעד מוקצה פעם אחת לסשן: סריקה מלאה קוראת מעל מיליון צמתים.
class _TreeSession {
  final int treeHandle;
  final HANDLE process;
  final Pointer remoteItem;
  final Pointer remoteText;

  /// האם הודעת קריאה אחת לפחות לא נענתה — חלון תקוע, סגור, או חסום.
  bool failed = false;

  /// הודעת קריאה. `null` (לא נענתה) נרשם ב-[failed], ומוחזר `0` — מה
  /// שהמתקשר ממילא מפרש כ"אין".
  int _read(
    int message, {
    int wParam = 0,
    int lParam = 0,
    int timeoutMs = 5000,
  }) {
    final result = ResponsaWin32.send(
      treeHandle,
      message,
      wParam: wParam,
      lParam: lParam,
      timeoutMs: timeoutMs,
    );
    if (result == null) failed = true;
    return result ?? 0;
  }

  /// `TVITEMW` חייב להיכתב בפריסת 32-ביט של היעד; פריסה שגויה מחזירה טקסט
  /// ריק ו-`lParam` אפס בלי שום שגיאה.
  static const int itemSize32 = 40;

  /// היסטי השדות בפריסת 32-ביט.
  static const int _offMask = 0;
  static const int _offItem = 4;
  static const int _offText = 16;
  static const int _offTextMax = 20;
  static const int _offChildren = 32;
  static const int _offParam = 36;

  static const int _tvifText = 0x0001;
  static const int _tvifParam = 0x0004;
  static const int _tvifChildren = 0x0040;

  /// כמה תווים להקצות לטקסט של צומת.
  static const int _textChars = 512;

  static const int _processVmOperation = 0x0008;
  static const int _processVmRead = 0x0010;
  static const int _processVmWrite = 0x0020;
  static const int _processQueryInformation = 0x0400;
  static const int _memCommit = 0x1000;
  static const int _memReserve = 0x2000;
  static const int _memRelease = 0x8000;
  static const int _pageReadWrite = 0x04;

  _TreeSession._({
    required this.treeHandle,
    required this.process,
    required this.remoteItem,
    required this.remoteText,
  });

  static _TreeSession? open(int pid, int treeHandle) {
    final process = OpenProcess(
      PROCESS_ACCESS_RIGHTS(
        _processVmOperation |
            _processVmRead |
            _processVmWrite |
            _processQueryInformation,
      ),
      false,
      pid,
    ).value;
    if (process.address == 0) {
      // מלמעלה "אין גישה" נראה כמו "העץ ריק" - זה הסימן היחיד.
      debugPrint(
        'ResponsaTreeReader: OpenProcess($pid) נכשל — '
        'ייתכן שבר אילן רץ בהרשאה גבוהה יותר מאוצריא',
      );
      return null;
    }

    final remoteItem = VirtualAllocEx(
      process,
      nullptr,
      itemSize32 + _textChars * 2,
      VIRTUAL_ALLOCATION_TYPE(_memCommit | _memReserve),
      PAGE_PROTECTION_FLAGS(_pageReadWrite),
    ).value;
    if (remoteItem.address == 0) {
      debugPrint('ResponsaTreeReader: VirtualAllocEx בתהליך $pid נכשל');
      CloseHandle(process);
      return null;
    }
    return _TreeSession._(
      treeHandle: treeHandle,
      process: process,
      remoteItem: remoteItem,
      remoteText: Pointer.fromAddress(remoteItem.address + itemSize32),
    );
  }

  void close() {
    VirtualFreeEx(process, remoteItem, 0, VIRTUAL_FREE_TYPE(_memRelease));
    CloseHandle(process);
  }

  int get root => _read(
    ResponsaTreeReader.tvmGetNextItem,
    wParam: ResponsaTreeReader.tvgnRoot,
  );

  /// מרחיב צומת ומחזיר את ידית ילדו הראשון, או `0`.
  int firstChild(int item) {
    _read(
      ResponsaTreeReader.tvmExpand,
      wParam: ResponsaTreeReader.tveExpand,
      lParam: item,
      timeoutMs: 8000,
    );
    return _read(
      ResponsaTreeReader.tvmGetNextItem,
      wParam: ResponsaTreeReader.tvgnChild,
      lParam: item,
    );
  }

  int nextSibling(int item) => _read(
    ResponsaTreeReader.tvmGetNextItem,
    wParam: ResponsaTreeReader.tvgnNext,
    lParam: item,
  );

  /// פריטים טעונים משביתים את התוכנה בכל `WM_SETTINGCHANGE`, ולכן מוחקים (העץ
  /// עצל ויתמלא מחדש). קיפול לפני מחיקה, אחרת היא איטית פי 40.
  void collapse(int item) {
    for (final action in const [
      ResponsaTreeReader.tveCollapse,
      ResponsaTreeReader.tveCollapse | ResponsaTreeReader.tveCollapseReset,
    ]) {
      ResponsaWin32.send(
        treeHandle,
        ResponsaTreeReader.tvmExpand,
        wParam: action,
        lParam: item,
        timeoutMs: 30000,
      );
    }
  }

  ({String name, int param, int children}) readItem(int item) {
    // בונים `TVITEMW` בפריסת 32-ביט ומעתיקים אותו לזיכרון היעד.
    final local = calloc<Uint8>(itemSize32);
    try {
      final bytes = local.asTypedList(itemSize32).buffer.asByteData();
      bytes.setUint32(
        _offMask,
        _tvifText | _tvifParam | _tvifChildren,
        Endian.little,
      );
      bytes.setUint32(_offItem, item, Endian.little);
      bytes.setUint32(_offText, remoteText.address, Endian.little);
      bytes.setInt32(_offTextMax, _textChars, Endian.little);

      final written = calloc<IntPtr>();
      try {
        WriteProcessMemory(process, remoteItem, local, itemSize32, written);
      } finally {
        calloc.free(written);
      }

      final ok = _read(
        ResponsaTreeReader.tvmGetItemW,
        lParam: remoteItem.address,
        timeoutMs: 8000,
      );
      if (ok == 0) return (name: '', param: 0, children: 0);

      final readBack = calloc<Uint8>(itemSize32);
      final textBuffer = calloc<Uint16>(_textChars);
      final read = calloc<IntPtr>();
      try {
        ReadProcessMemory(process, remoteItem, readBack, itemSize32, read);
        ReadProcessMemory(
          process,
          remoteText,
          textBuffer,
          _textChars * 2,
          read,
        );
        final view = readBack.asTypedList(itemSize32).buffer.asByteData();
        return (
          name: _utf16At(textBuffer, _textChars),
          param: view.getUint32(_offParam, Endian.little),
          children: view.getInt32(_offChildren, Endian.little),
        );
      } finally {
        calloc.free(readBack);
        calloc.free(textBuffer);
        calloc.free(read);
      }
    } finally {
      calloc.free(local);
    }
  }

  static String _utf16At(Pointer<Uint16> buffer, int maxChars) {
    final units = buffer.asTypedList(maxChars);
    final end = units.indexOf(0);
    return String.fromCharCodes(units.sublist(0, end < 0 ? maxChars : end));
  }
}

/// מצב סריקה אחת: הצמתים שנאספו והקולבקים.
class _Walk {
  final _TreeSession session;
  final void Function(int)? onProgress;
  final bool Function()? shouldStop;
  final int progressEvery;
  final int maxNodes;
  final nodes = <ResponsaTreeNode>[];

  /// המחיקה משביתה את התוכנה בזמן שהיא רצה: ענף רמה 2 הגדול ביותר הוא ~28 אלף
  /// צמתים (פחות משנייה), ברמה 1 מאות אלפים (כתשע שניות).
  static const int _collapseDepth = 2;

  _Walk({
    required this.session,
    required this.onProgress,
    required this.shouldStop,
    required this.progressEvery,
    required this.maxNodes,
  });

  /// קורא את [item] ואת כל צאצאיו. `false` כשהסריקה נעצרה באמצע.
  bool visit(int item, int level, List<String> parentPath) {
    if (nodes.length >= maxNodes) return false;
    if (nodes.length % progressEvery == 0) {
      if (shouldStop?.call() ?? false) return false;
      onProgress?.call(nodes.length);
    }

    final read = session.readItem(item);
    if (session.failed) return false;
    final path = [...parentPath, read.name];
    nodes.add(
      ResponsaTreeNode(
        name: read.name,
        param: read.param,
        level: level,
        path: path.join(ResponsaTreeReader.pathSeparator),
        childCount: read.children,
      ),
    );
    if (read.children == 0) return true;

    // חובה להרחיב לפני קריאת הילדים — העץ נטען עצלנית.
    var completed = true;
    for (
      var child = session.firstChild(item);
      child != 0;
      child = session.nextSibling(child)
    ) {
      if (!visit(child, level + 1, path)) {
        completed = false;
        break;
      }
    }
    // גם בביטול: ענף שהורחב ולא נמחק נשאר טעון בתוכנה.
    if (level <= _collapseDepth) session.collapse(item);
    return completed;
  }
}

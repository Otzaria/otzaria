import 'package:flutter/foundation.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// טאב המציג שני ספרים זה לצד זה, עם מפריד ניתן לגרירה.
///
/// שתי החלוניות הן תמיד עלים — פיצול אינו מקונן, ולכן בטאב יש בדיוק שתי
/// חלוניות. מצב שנשמר בגרסה שתמכה בקינון מנורמל ב-[flattenRestoredSplits].
///
/// סגירת הטאב סוגרת את שתי החלוניות שבו.
class CombinedTab extends OpenedTab {
  /// החלונית הראשונה בסדר התצוגה — הימנית ב-RTL.
  final OpenedTab rightTab;

  /// החלונית השנייה בסדר התצוגה — השמאלית ב-RTL.
  final OpenedTab leftTab;

  /// חלקה של [rightTab] מהמקום הפנוי (0.0-1.0).
  ///
  /// משתנה במקום (mutable) בכוונה: גרירת המפריד לא אמורה ליצור טאב חדש,
  /// שהיה מחליף את מפתחות החלוניות ומאתחל מחדש את תוכנן.
  double splitRatio;

  CombinedTab({
    required this.rightTab,
    required this.leftTab,
    this.splitRatio = 0.5,
    bool isPinned = false,
  }) : super('', isPinned: isPinned);

  /// מחושבת בכל קריאה: כותרת חלונית משתנה אחרי טעינת הספר, וכותרת שהוקפאה
  /// בבנייה נשארה מיושנת ב-tooltip וברשימת הקיצורים של Windows.
  @override
  String get title => 'משולב: ${rightTab.title} | ${leftTab.title}';

  /// הכותרת נגזרת מהחלוניות; השדה שבבסיס אינו נקרא, ולכן כתיבה אליו נבלעת
  /// בשקט. חוסמים אותה במפורש כדי שהמלכוד לא יתגלה רק בזמן ריצה.
  @override
  set title(String value) =>
      throw UnsupportedError('כותרת טאב מפוצל נגזרת מהחלוניות שבו');

  /// שתי החלוניות בסדר התצוגה.
  List<OpenedTab> get panes => [rightTab, leftTab];

  /// האחות של [pane], או `null` אם [pane] אינה אחת משתי החלוניות.
  OpenedTab? sibling(OpenedTab pane) {
    if (identical(pane, rightTab)) return leftTab;
    if (identical(pane, leftTab)) return rightTab;
    return null;
  }

  /// יוצרת עותק עם חלוניות מוחלפות, תוך שמירת [splitRatio] וההצמדה.
  CombinedTab copyWith({
    OpenedTab? rightTab,
    OpenedTab? leftTab,
    double? splitRatio,
    bool? isPinned,
  }) {
    return CombinedTab(
      rightTab: rightTab ?? this.rightTab,
      leftTab: leftTab ?? this.leftTab,
      splitRatio: splitRatio ?? this.splitRatio,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  /// משחררת את הטאב ואת שתי החלוניות שבו.
  @override
  void dispose() {
    rightTab.dispose();
    leftTab.dispose();
    super.dispose();
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'rightTab': rightTab.toJson(),
      'leftTab': leftTab.toJson(),
      'splitRatio': splitRatio,
      'isPinned': isPinned,
      'type': 'CombinedTab',
    };
  }
}

/// מפענחת טאב מפוצל שנשמר.
///
/// חלונית שפענוחה נכשל — טיפוס מגרסה חדשה יותר, שדה פגום — מוסרת ואחותה
/// חוזרת ככרטיסייה רגילה. בלי זה ספר תקין היה נמחק בגלל שכנתו.
OpenedTab decodeCombinedTab(Map<String, dynamic> json) {
  OpenedTab? decodePane(dynamic raw) {
    try {
      final map = castMap(raw);
      if (map['type'] == 'PdfCommentatorsTab') {
        return PdfCommentatorsTab.fromJson(map);
      }
      if (map['type'] == 'CommentatorsTab') {
        return CommentatorsTab.fromJson(map);
      }
      return OpenedTab.fromJson(map);
    } catch (e) {
      debugPrint('⚠️ Skipping split pane that failed to restore: $e');
      return null;
    }
  }

  final right = decodePane(json['rightTab']);
  final left = decodePane(json['leftTab']);
  final isPinned = json['isPinned'] == true;

  if (right == null || left == null) {
    final survivor = right ?? left;
    if (survivor == null) {
      throw const FormatException('טאב מפוצל ללא חלונית שניתן לשחזר');
    }
    if (isPinned) survivor.isPinned = true;
    return survivor;
  }

  return CombinedTab(
    rightTab: right,
    leftTab: left,
    splitRatio: ((json['splitRatio'] as num?)?.toDouble() ?? 0.5).clamp(
      0.0,
      1.0,
    ),
    isPinned: isPinned,
  );
}

/// חלוניות התוכן של טאב: שתיים בטאב מפוצל, אחת בכל שאר הטאבים.
List<OpenedTab> leafPanes(OpenedTab tab) =>
    tab is CombinedTab ? [tab.rightTab, tab.leftTab] : [tab];

/// מסירה מטאב מפוצל חלונית ש-[keep] דוחה; האחות תופסת את מקום הטאב.
///
/// מחזירה `null` כשלא נותרה אף חלונית, ואת הטאב עצמו כשלא השתנה דבר — כדי
/// שהחלוניות שנשמרו לא יאבדו את זהותן.
OpenedTab? prunePanes(OpenedTab tab, bool Function(OpenedTab pane) keep) {
  if (tab is! CombinedTab) return keep(tab) ? tab : null;

  final keepRight = keep(tab.rightTab);
  final keepLeft = keep(tab.leftTab);
  if (keepRight && keepLeft) return tab;
  if (keepRight) return tab.rightTab;
  if (keepLeft) return tab.leftTab;
  return null;
}

/// מנרמלת טאבים ששוחזרו מדיסק לפיצול דו-חלוניתי, יחד עם האינדקס הפעיל.
///
/// שמירה מגרסה שתמכה בפיצול מקונן יכולה להחזיר טאב עם יותר משתי חלוניות;
/// שתי הראשונות נשארות מפוצלות והשאר חוזרות ככרטיסיות עצמאיות, כדי שספר
/// שהיה פתוח לא ייעלם.
///
/// [currentIndex] מוחזר מעודכן: הכרטיסיות שנוספו דוחפות קדימה כל מה שאחריהן,
/// ובלי התיקון האינדקס השמור היה מצביע על ספר אחר.
({List<OpenedTab> tabs, int currentIndex}) flattenRestoredSplits(
  List<OpenedTab> tabs, {
  int currentIndex = 0,
}) {
  final normalized = <OpenedTab>[];
  var normalizedIndex = currentIndex;
  for (var i = 0; i < tabs.length; i++) {
    final tab = tabs[i];
    if (tab is! CombinedTab) {
      normalized.add(tab);
      continue;
    }
    final leaves = _allLeaves(tab);
    if (leaves.length == 2) {
      normalized.add(tab);
      continue;
    }
    normalized.add(
      CombinedTab(
        rightTab: leaves[0],
        leftTab: leaves[1],
        splitRatio: tab.splitRatio,
        isPinned: tab.isPinned,
      ),
    );
    for (final extra in leaves.skip(2)) {
      // ההצמדה נשמרה על הטאב המפוצל; חלונית שיוצאת ממנו ככרטיסייה עצמאית
      // יורשת אותה, אחרת "סגור הכל" היה סוגר ספר שהמשתמש נעץ.
      if (tab.isPinned) extra.isPinned = true;
      normalized.add(extra);
    }
    if (i < currentIndex) normalizedIndex += leaves.length - 2;
  }
  return (tabs: normalized, currentIndex: normalizedIndex);
}

/// כל חלוניות התוכן שתחת [tab], כולל פיצול מקונן ששוחזר מגרסה קודמת.
List<OpenedTab> _allLeaves(OpenedTab tab) => tab is CombinedTab
    ? [..._allLeaves(tab.rightTab), ..._allLeaves(tab.leftTab)]
    : [tab];

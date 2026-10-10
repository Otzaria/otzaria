import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// שם "שולחן עבודה N" שאינו תפוס עדיין ב-[existingWorkspaces].
String uniqueWorkspaceName(List<Workspace> existingWorkspaces) {
  final existingNames = existingWorkspaces.map((w) => w.name).toSet();
  int counter = existingWorkspaces.length + 1;

  while (true) {
    final candidateName = "שולחן עבודה $counter";
    if (!existingNames.contains(candidateName)) {
      return candidateName;
    }
    counter++;
  }
}

/// Represents a workspace in the application.
///
/// A `Workspace` object has a unique [id], a [name],
/// a list of [tabs], and the [activeTabIndex].
///
/// This class is immutable - use [copyWith] to create modified copies.
class Workspace extends Equatable {
  final String id;
  final String name;
  final List<OpenedTab> tabs;
  final int activeTabIndex;

  /// צד החלונית הפעילה בטאב שב-[activeTabIndex] — [kRightPaneSide] או
  /// [kLeftPaneSide]. `null` כשהטאב הפעיל אינו מפוצל, וזה גם המצב היחיד
  /// שבו המפתח נעדר מה-JSON.
  ///
  /// הערך יושב ברמת שולחן העבודה ולא בתוך [CombinedTab.toJson], כי
  /// משמעותו "איזו חלונית פעילה **בטאב הנוכחי**" — נתון אחד לשולחן עבודה,
  /// בדיוק כמו [activeTabIndex].
  final String? activePane;

  /// שולחן מקובע: מעבר לשולחן אחר אינו דורס את הכרטיסיות השמורות בו, והן
  /// מתעדכנות רק בשמירה מפורשת.
  final bool isPinned;

  Workspace({
    String? id,
    required this.name,
    required this.tabs,
    this.activeTabIndex = 0,
    this.activePane,
    this.isPinned = false,
  }) : id = id ?? _generateId();

  static int _idCounter = 0;

  /// Generates a unique ID using monotonic counter + microsecond timestamp.
  /// The counter guarantees uniqueness even when called multiple times within
  /// the same microsecond (e.g. in tests or fast programmatic creation).
  static String _generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
  }

  /// Creates a copy of this workspace with the given fields replaced.
  ///
  /// [activePane] אינו פרמטר כאן בכוונה: `String?` לא היה מבחין בין
  /// "אל תיגע" לבין "נקה". להחלפת תוכן השתמשו ב-[withTabs].
  Workspace copyWith({
    String? name,
    List<OpenedTab>? tabs,
    int? activeTabIndex,
    bool? isPinned,
  }) {
    return Workspace(
      id: id, // ID remains the same
      name: name ?? this.name,
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      activePane: activePane,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  /// מחליף את תוכן שולחן העבודה. שלושת השדות נקבעים **יחד**: צד החלונית
  /// הפעילה חסר משמעות בלי הטאבים שאליהם הוא מתייחס, ו-`null` כאן פירושו
  /// תמיד "אין חלונית פעילה" ולא "אל תיגע".
  Workspace withTabs({
    required List<OpenedTab> tabs,
    required int activeTabIndex,
    required String? activePane,
  }) {
    return Workspace(
      id: id,
      name: name,
      tabs: tabs,
      activeTabIndex: activeTabIndex,
      activePane: activePane,
      isPinned: isPinned,
    );
  }

  /// טאבי מפרשי PDF אינם נשמרים בשולחן עבודה: שחזורם בונה `sourceTab` חדש
  /// במקום להתחבר לספר החי. חלונית כזו בטאב מפוצל מוסרת, ואחותה תופסת את
  /// מקום הטאב.
  static OpenedTab? _withoutPdfCommentators(OpenedTab tab) =>
      prunePanes(tab, (pane) => pane is! PdfCommentatorsTab);

  factory Workspace.fromJson(Map<String, dynamic> json) {
    OpenedTab? decodeTab(Map<String, dynamic> map) {
      // ⚠️ סינון מדיניות ולא מגבלת מפענח: `OpenedTab.fromJson` **כן** מכיר
      // את הטיפוס, אבל שחזור טאב מפרשי PDF בשולחן עבודה בונה `sourceTab`
      // חדש במקום להתחבר לספר החי (ראו [_withoutPdfCommentators]).
      if (map['type'] == 'PdfCommentatorsTab') return null;
      try {
        return OpenedTab.fromJson(map);
      } catch (e) {
        // טאב בודד פגום (למשל טיפוס מגרסה חדשה יותר) לא יפיל את פענוח
        // שולחן העבודה כולו.
        debugPrint('⚠️ Skipping workspace tab that failed to restore: $e');
        return null;
      }
    }

    final rawTabs = json['tabs'] as List? ?? const [];
    final savedIndex = json['currentTab'] as int? ?? 0;
    final decoded = <OpenedTab>[];
    var currentIndex = 0;
    for (var i = 0; i < rawTabs.length; i++) {
      final tab = decodeTab(castMap(rawTabs[i]));
      if (tab == null) continue;
      if (i <= savedIndex) currentIndex = decoded.length;
      decoded.add(tab);
    }

    // הגיזום אחרי הנירמול: בפיצול מקונן ששוחזר מגרסה קודמת חלונית מפרשי
    // PDF יכולה לשבת בעומק שאליו הגיזום אינו יורד.
    final restored = flattenRestoredSplits(
      decoded,
      currentIndex: currentIndex,
    );
    final tabs = restored.tabs
        .map(_withoutPdfCommentators)
        .whereType<OpenedTab>()
        .toList();

    // ערך פגום, או מפתח מגרסה עתידית, נקרא כ-null ואינו מפיל את השחזור:
    // `paneForSide` יחזיר null והחלונית הפעילה תיפול ל-`panes.first`.
    final rawSide = json['activePane'];
    final side = rawSide == kRightPaneSide || rawSide == kLeftPaneSide
        ? rawSide as String
        : null;

    return Workspace(
      id: json['id'] as String?,
      name: json['name'] as String,
      tabs: tabs,
      activeTabIndex: tabs.isEmpty
          ? 0
          : restored.currentIndex.clamp(0, tabs.length - 1),
      activePane: side,
      isPinned: json['isPinned'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final persistedTabs = <OpenedTab>[];
    var remappedIndex = 0;
    for (var i = 0; i < tabs.length; i++) {
      final pruned = _withoutPdfCommentators(tabs[i]);
      if (pruned == null) continue;
      if (i <= activeTabIndex) remappedIndex = persistedTabs.length;
      persistedTabs.add(pruned);
    }
    final safeIndex = persistedTabs.isEmpty
        ? 0
        : remappedIndex.clamp(0, persistedTabs.length - 1);
    // ⚠️ הצד נקבע מהטאב **שאחרי** הגיזום והמיפוי מחדש. `prunePanes` יכול
    // להחליף טאב מפוצל בחלונית הבודדת ששרדה, ואז "right"/"left" חסר
    // משמעות — ולכן המפתח פשוט לא נכתב.
    final persistedActiveTab = persistedTabs.isEmpty
        ? null
        : persistedTabs[safeIndex];
    final persistedSide = persistedActiveTab is CombinedTab ? activePane : null;
    return {
      'id': id,
      'name': name,
      'tabs': persistedTabs.map((tab) => tab.toJson()).toList(),
      'currentTab': safeIndex,
      'activePane': ?persistedSide,
      if (isPinned) 'isPinned': true,
    };
  }

  @override
  List<Object?> get props => [
    id,
    name,
    tabs,
    activeTabIndex,
    activePane,
    isPinned,
  ];
}

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

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

  Workspace({
    String? id,
    required this.name,
    required this.tabs,
    this.activeTabIndex = 0,
  }) : id = id ?? _generateId();

  static int _idCounter = 0;

  /// Generates a unique ID using monotonic counter + microsecond timestamp.
  /// The counter guarantees uniqueness even when called multiple times within
  /// the same microsecond (e.g. in tests or fast programmatic creation).
  static String _generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
  }

  /// Creates a copy of this workspace with the given fields replaced.
  Workspace copyWith({
    String? name,
    List<OpenedTab>? tabs,
    int? activeTabIndex,
  }) {
    return Workspace(
      id: id, // ID remains the same
      name: name ?? this.name,
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }

  /// טאבי מפרשי PDF אינם נשמרים בשולחן עבודה: שחזורם בונה `sourceTab` חדש
  /// במקום להתחבר לספר החי. חלונית כזו בטאב מפוצל מוסרת, ואחותה תופסת את
  /// מקום הטאב.
  static OpenedTab? _withoutPdfCommentators(OpenedTab tab) =>
      prunePanes(tab, (pane) => pane is! PdfCommentatorsTab);

  factory Workspace.fromJson(Map<String, dynamic> json) {
    OpenedTab? decodeTab(Map<String, dynamic> map) {
      // הסינון לפני הפענוח, כי `OpenedTab.fromJson` אינו מכיר את הטיפוס.
      if (map['type'] == 'PdfCommentatorsTab') return null;
      try {
        return map['type'] == 'CommentatorsTab'
            ? CommentatorsTab.fromJson(map)
            : OpenedTab.fromJson(map);
      } catch (e) {
        // טאב בודד פגום (למשל טיפוס מגרסה חדשה יותר) לא יפיל את פענוח
        // שולחן העבודה כולו.
        debugPrint('⚠️ Skipping workspace tab that failed to restore: $e');
        return null;
      }
    }

    final decoded =
        (json['tabs'] as List?)
            ?.map((raw) => decodeTab(castMap(raw)))
            .whereType<OpenedTab>()
            .toList() ??
        <OpenedTab>[];

    // הגיזום אחרי הנירמול: בפיצול מקונן ששוחזר מגרסה קודמת חלונית מפרשי
    // PDF יכולה לשבת בעומק שאליו הגיזום אינו יורד.
    final restored = flattenRestoredSplits(
      decoded,
      currentIndex: json['currentTab'] as int? ?? 0,
    );
    final tabs = restored.tabs
        .map(_withoutPdfCommentators)
        .whereType<OpenedTab>()
        .toList();

    return Workspace(
      id: json['id'] as String?,
      name: json['name'] as String,
      tabs: tabs,
      activeTabIndex: tabs.isEmpty
          ? 0
          : restored.currentIndex.clamp(0, tabs.length - 1),
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
    return {
      'id': id,
      'name': name,
      'tabs': persistedTabs.map((tab) => tab.toJson()).toList(),
      'currentTab': safeIndex,
    };
  }

  @override
  List<Object?> get props => [id, name, tabs, activeTabIndex];
}

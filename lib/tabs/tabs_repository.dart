import 'dart:async';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/utils/file/hive_utils.dart';
import 'package:flutter/foundation.dart';

class TabsRepository {
  static const String _tabsBoxKey = 'key-tabs';
  static const String _currentTabKey = 'key-current-tab';
  static const String _sideBySideModeKey = 'key-side-by-side-mode';

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

  SideBySideMode? _resolvePersistedSideBySideMode(
    SideBySideMode? sideBySideMode,
    Map<int, int> persistedIndexByOriginalIndex,
  ) {
    if (sideBySideMode == null) return null;

    final persistedLeft =
        persistedIndexByOriginalIndex[sideBySideMode.leftTabIndex];
    final persistedRight =
        persistedIndexByOriginalIndex[sideBySideMode.rightTabIndex];

    if (persistedLeft == null ||
        persistedRight == null ||
        persistedLeft == persistedRight) {
      return null;
    }

    return SideBySideMode(
      leftTabIndex: persistedLeft,
      rightTabIndex: persistedRight,
      splitRatio: sideBySideMode.splitRatio,
    );
  }

  /// ממפה נתיבי קבצים שמורים של טאבים מתיקיית הספרייה הישנה [fromDir] לחדשה
  /// [toDir], כדי שספרי PDF/DOCX פתוחים ייטענו מהמיקום החדש לאחר רענון התוכנה.
  /// משכתב את שדות 'path' ו-'filePath' בכל עומק (כולל ה-book המקונן).
  Future<void> remapBookPaths(String fromDir, String toDir) async {
    final box = Hive.box('tabs');
    final rawTabs = box.get(_tabsBoxKey, defaultValue: []) as List;
    var changed = false;
    final remapped = rawTabs
        .map((e) => _remapNode(e, fromDir, toDir, () => changed = true))
        .toList();
    if (changed) await box.put(_tabsBoxKey, remapped);
  }

  /// ממפה נתיבי קבצים של טאבים פתוחים *בזיכרון* מ-[fromDir] ל-[toDir].
  /// טאב שהנתיב שלו לא משתנה מוחזר כאובייקט המקורי (ללא בנייה מחדש);
  /// טאב ששונה נבנה מחדש דרך toJson→fromJson עם הנתיב החדש.
  /// נדרש בנוסף ל-[remapBookPaths]: שמירה ל-Hive בלבד נדרסת ע"י שמירת
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
      return _tabFromJson(castMap(remappedJson)) ?? tab;
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

  /// הטאבים כפי שנשמרו. פיצול מקונן מגרסה קודמת מנורמל אצל הקורא דרך
  /// [flattenRestoredSplits], יחד עם האינדקס הפעיל — שהנירמול מזיז.
  List<OpenedTab> loadTabs() {
    try {
      final box = Hive.box('tabs');
      final rawTabs = box.get(_tabsBoxKey, defaultValue: []) as List;
      final tabs = <OpenedTab>[];
      for (final e in rawTabs) {
        try {
          final tab = _tabFromJson(castMap(e));
          if (tab != null) tabs.add(tab);
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

  /// כמו OpenedTab.fromJson אבל תומך גם ב-CommentatorsTab וב-PdfCommentatorsTab.
  OpenedTab? _tabFromJson(Map<String, dynamic> json) {
    if (json['type'] == 'CommentatorsTab') {
      return CommentatorsTab.fromJson(json);
    }
    if (json['type'] == 'PdfCommentatorsTab') {
      return PdfCommentatorsTab.fromJson(json);
    }
    return OpenedTab.fromJson(json);
  }

  int loadCurrentTabIndex() {
    return Hive.box('tabs').get(_currentTabKey, defaultValue: 0);
  }

  SideBySideMode? loadSideBySideMode() {
    try {
      final box = Hive.box('tabs');
      final rawMode = box.get(_sideBySideModeKey);
      if (rawMode == null) return null;
      return SideBySideMode.fromJson(castMap(rawMode));
    } catch (e) {
      debugPrint('Error loading side-by-side mode from disk: $e');
      return null;
    }
  }

  Future<void> saveTabs(
    List<OpenedTab> tabs,
    int currentTabIndex, [
    SideBySideMode? sideBySideMode,
  ]) async {
    final box = Hive.box('tabs');
    final persistedTabs = <OpenedTab>[];
    final persistedIndexByOriginalIndex = <int, int>{};

    for (var i = 0; i < tabs.length; i++) {
      persistedIndexByOriginalIndex[i] = persistedTabs.length;
      persistedTabs.add(tabs[i]);
    }

    final persistedCurrentIndex = _resolvePersistedCurrentTabIndex(
      persistedIndexByOriginalIndex,
      currentTabIndex,
      tabs.length,
    );
    final persistedSideBySideMode = _resolvePersistedSideBySideMode(
      sideBySideMode,
      persistedIndexByOriginalIndex,
    );

    await box.put(
      _tabsBoxKey,
      persistedTabs.map((tab) => tab.toJson()).toList(),
    );
    await box.put(_currentTabKey, persistedCurrentIndex);
    if (persistedSideBySideMode != null) {
      await box.put(_sideBySideModeKey, persistedSideBySideMode.toJson());
    } else {
      await box.delete(_sideBySideModeKey);
    }
  }

  /// שומר רק את אינדקס הטאב הנוכחי, בלי לקודד מחדש את כל הטאבים.
  ///
  /// מיועד למעבר בין טאבים, שבו רשימת הטאבים עצמה לא משתנה — אין טעם
  /// להריץ `toJson()` על כל הטאבים בכל מעבר. מבצע רק מיפוי אינדקסים קל
  /// ושומר ערך בודד. הכתיבה ל-Hive אסינכרונית ואינה חוסמת את ה-UI.
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {
    final persistedIndexByOriginalIndex = <int, int>{};
    var persistedCount = 0;
    for (var i = 0; i < tabs.length; i++) {
      persistedIndexByOriginalIndex[i] = persistedCount;
      persistedCount++;
    }

    final persistedCurrentIndex = _resolvePersistedCurrentTabIndex(
      persistedIndexByOriginalIndex,
      currentTabIndex,
      tabs.length,
    );

    await Hive.box('tabs').put(_currentTabKey, persistedCurrentIndex);
  }
}

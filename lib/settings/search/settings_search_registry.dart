import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';

/// בקשת ניווט לתוצאת חיפוש — נשלחת מ-SearchResults אל מסך ההגדרות.
class SettingsSearchNavigationRequest {
  final SettingsTab tab;
  final String? cardId;
  final String? expandSection;
  final String entryId;
  final DateTime requestedAt;

  SettingsSearchNavigationRequest({
    required this.tab,
    required this.cardId,
    required this.expandSection,
    required this.entryId,
  }) : requestedAt = DateTime.now();
}

/// רישום מרכזי של אנכורי כרטיסים + ניהול בקשות ניווט והדגשה.
///
/// - כל SettingsAnchor מרשם את ה-GlobalKey שלו במפה לפי cardId.
/// - תוצאות חיפוש שולחות navigateToEntry → מתעדכן _pendingRequest.
/// - מסך ההגדרות מאזין ומעביר ל-tab המתאים, ואז קורא scrollAndHighlight.
/// - SettingsAnchor מאזין ל-notifier של הכרטיס ומפעיל אנימציית הבזק.
class SettingsSearchRegistry extends ChangeNotifier {
  SettingsSearchRegistry._();
  static final SettingsSearchRegistry instance = SettingsSearchRegistry._();

  final Map<String, GlobalKey> _anchors = {};
  final Map<String, ValueNotifier<bool>> _flashNotifiers = {};
  final Map<String, ValueChanged<String>> _sectionOpeners = {};

  SettingsSearchNavigationRequest? _pendingRequest;
  SettingsSearchNavigationRequest? get pendingRequest => _pendingRequest;

  /// רישום אנכור על ידי SettingsAnchor (קריאה מ-initState).
  void registerAnchor(String cardId, GlobalKey key) {
    _anchors[cardId] = key;
    _flashNotifiers.putIfAbsent(cardId, () => ValueNotifier<bool>(false));
  }

  /// הסרת רישום (מ-dispose).
  void unregisterAnchor(String cardId, GlobalKey key) {
    if (_anchors[cardId] == key) {
      _anchors.remove(cardId);
    }
  }

  /// Lets the card [cardId] open the part of it that a result's
  /// `expandSection` names, when that part is not on the page itself.
  void registerSectionOpener(String cardId, ValueChanged<String> open) {
    _sectionOpeners[cardId] = open;
  }

  void unregisterSectionOpener(String cardId, ValueChanged<String> open) {
    if (_sectionOpeners[cardId] == open) _sectionOpeners.remove(cardId);
  }

  /// מציין שזה הזמן להבזיק על cardId נתון (מאזינים ב-SettingsAnchor).
  ValueListenable<bool> flashNotifierFor(String cardId) {
    return _flashNotifiers.putIfAbsent(
      cardId,
      () => ValueNotifier<bool>(false),
    );
  }

  /// בקשת ניווט לתוצאת חיפוש.
  /// מסך ההגדרות יזהה את הבקשה, יעבור לטאב, ולאחר טעינת הטאב יקרא
  /// scrollAndHighlight כדי להשלים את הניווט.
  void navigateToEntry(SettingsSearchEntry entry) {
    _pendingRequest = SettingsSearchNavigationRequest(
      tab: entry.tab,
      cardId: entry.cardId,
      expandSection: entry.expandSection,
      entryId: entry.id,
    );
    notifyListeners();
  }

  /// סימון שהבקשה הנוכחית נצרכה (כדי לא לעבד אותה שוב).
  void consumePendingRequest() {
    _pendingRequest = null;
  }

  /// גלילה לאנכור והבזק קצר. נקראת מהטאב לאחר build.
  /// כשהטאב עוד לא נבנה, ה-context לא זמין מיד — לכן ננסה כמה פעמים
  /// (עד ~720ms) לפני ויתור, כדי לכסות build איטי או anchors שעוד
  /// לא נכנסו לעץ.
  Future<void> scrollAndHighlight(String cardId, {String? section}) async {
    BuildContext? ctx;
    for (var attempt = 0; attempt < 12; attempt++) {
      ctx = _anchors[cardId]?.currentContext;
      if (ctx != null && ctx.mounted) break;
      await Future.delayed(const Duration(milliseconds: 60));
    }
    if (ctx == null || !ctx.mounted) return;

    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );

    final openSection = _sectionOpeners[cardId];
    if (section != null && openSection != null) {
      openSection(section);
      return;
    }

    final notifier = _flashNotifiers[cardId];
    if (notifier != null) {
      notifier.value = true;
      await Future.delayed(const Duration(milliseconds: 1400));
      notifier.value = false;
    }
  }
}

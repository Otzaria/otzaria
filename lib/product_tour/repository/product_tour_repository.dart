import 'dart:convert';

import 'package:otzaria/product_tour/models/product_tour_models.dart';
import 'package:otzaria/settings/engine/settings_wrapper.dart';

/// מנהל את השמירה המתמשכת של מצב הסיור והטיפים החיים.
class ProductTourRepository {
  static const String keyProductTourStatus = 'key-product-tour-v1-status';
  static const String keyProductTourLastStep = 'key-product-tour-v1-last-step';
  static const String keyLiveTipsShown = 'key-live-tips-v1-shown';
  static const String keyLiveTipsResolved = 'key-live-tips-v1-resolved';

  final SettingsWrapper _settings;

  ProductTourRepository({
    SettingsWrapper? settings,
  }) : _settings = settings ?? SettingsWrapper();

  /// טוען את סטטוס הסיור השמור.
  Future<ProductTourStatus> loadStatus() async {
    final rawStatus = _settings.getValue<String>(
      keyProductTourStatus,
      defaultValue: ProductTourStatus.unseen.name,
    );

    return ProductTourStatus.values.firstWhere(
      (status) => status.name == rawStatus,
      orElse: () => ProductTourStatus.unseen,
    );
  }

  /// שומר את סטטוס הסיור.
  Future<void> saveStatus(ProductTourStatus status) {
    return _settings.setValue<String>(keyProductTourStatus, status.name);
  }

  /// טוען את אינדקס השלב האחרון שנשמר.
  Future<int> loadLastStep() async {
    return _settings.getValue<int>(keyProductTourLastStep, defaultValue: 0);
  }

  /// שומר את אינדקס השלב הפעיל.
  Future<void> saveLastStep(int stepIndex) {
    return _settings.setValue<int>(keyProductTourLastStep, stepIndex);
  }

  /// טוען את רשימת הטיפים שכבר הוצגו למשתמש.
  Future<Set<LiveTipId>> loadShownTips() async {
    final rawJson = _settings.getValue<String>(
      keyLiveTipsShown,
      defaultValue: '[]',
    );
    return _decodeTipSet(rawJson);
  }

  /// טוען את רשימת הטיפים שכבר אינם רלוונטיים למשתמש.
  Future<Set<LiveTipId>> loadResolvedTips() async {
    final rawJson = _settings.getValue<String>(
      keyLiveTipsResolved,
      defaultValue: '[]',
    );
    return _decodeTipSet(rawJson);
  }

  /// שומר את קבוצת הטיפים שהוצגו.
  Future<void> saveShownTips(Set<LiveTipId> tipIds) {
    return _settings.setValue<String>(
      keyLiveTipsShown,
      jsonEncode(
        tipIds.map((tipId) => tipId.name).toList()..sort(),
      ),
    );
  }

  /// שומר את קבוצת הטיפים שנפתרו.
  Future<void> saveResolvedTips(Set<LiveTipId> tipIds) {
    return _settings.setValue<String>(
      keyLiveTipsResolved,
      jsonEncode(
        tipIds.map((tipId) => tipId.name).toList()..sort(),
      ),
    );
  }

  /// מאפס את כל נתוני הסיור והטיפים.
  Future<void> resetAll() async {
    await _settings.remove(keyProductTourStatus);
    await _settings.remove(keyProductTourLastStep);
    await _settings.remove(keyLiveTipsShown);
    await _settings.remove(keyLiveTipsResolved);
  }

  Set<LiveTipId> _decodeTipSet(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        return <LiveTipId>{};
      }

      return decoded
          .whereType<String>()
          .map(
            (tipName) => LiveTipId.values.firstWhere(
              (tipId) => tipId.name == tipName,
              orElse: () => LiveTipId.sideBySideSuggestion,
            ),
          )
          .where((tipId) => decoded.contains(tipId.name))
          .toSet();
    } catch (_) {
      return <LiveTipId>{};
    }
  }
}

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// ההגדרות שהחיפוש הסמנטי קורא וכותב.
abstract interface class SemanticSettingsStore {
  /// דיוק מודל השאילתות שנבחר.
  SemanticQuantization get quantization;
  Future<void> setQuantization(SemanticQuantization value);

  /// המשתמש הוריד את הנתונים, ולכן הם מתעדכנים ברקע אחרי עדכוני ספרייה.
  bool get dataEnabled;
  Future<void> setDataEnabled(bool value);

  /// המשתמש עצר את ההורדה; רק בקשה מפורשת מחדשת אותה.
  bool get downloadPaused;
  Future<void> setDownloadPaused(bool value);

  /// תג release וקטורים שאין להוריד שוב (פרסום חוזר של גרסה מותקנת).
  String? get skippedVectorsRelease;
  Future<void> setSkippedVectorsRelease(String? value);

  /// מצב לא מקוון: אין שום פנייה לרשת.
  bool get isOfflineMode;
}

/// המימוש מעל [Settings] של האפליקציה.
class SettingsSemanticSettingsStore implements SemanticSettingsStore {
  const SettingsSemanticSettingsStore();

  @override
  SemanticQuantization get quantization => SemanticQuantization.parse(
    Settings.getValue<String>(SettingsRepository.keySemanticModelQuantization),
  );

  @override
  Future<void> setQuantization(SemanticQuantization value) =>
      Settings.setValue<String>(
        SettingsRepository.keySemanticModelQuantization,
        value.name,
      );

  @override
  bool get dataEnabled =>
      Settings.getValue<bool>(SettingsRepository.keySemanticDataEnabled) ??
      false;

  @override
  Future<void> setDataEnabled(bool value) =>
      Settings.setValue<bool>(SettingsRepository.keySemanticDataEnabled, value);

  @override
  bool get downloadPaused =>
      Settings.getValue<bool>(SettingsRepository.keySemanticDownloadPaused) ??
      false;

  @override
  Future<void> setDownloadPaused(bool value) => Settings.setValue<bool>(
    SettingsRepository.keySemanticDownloadPaused,
    value,
  );

  @override
  String? get skippedVectorsRelease {
    final value = Settings.getValue<String>(
      SettingsRepository.keySemanticSkippedVectorsRelease,
    );
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> setSkippedVectorsRelease(String? value) =>
      Settings.setValue<String>(
        SettingsRepository.keySemanticSkippedVectorsRelease,
        value ?? '',
      );

  @override
  bool get isOfflineMode =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;
}

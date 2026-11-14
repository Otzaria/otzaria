import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// האם ספרי PDF נכנסים לאינדקס החיפוש. בלי הגדרות מאותחלות (בדיקות, בונה
/// אינדקס ההפצה) — כן.
bool readIndexPdfBooksSetting() {
  if (!Settings.isInitialized) return true;
  return Settings.getValue<bool>(SettingsRepository.keyIndexPdfBooks) ?? true;
}

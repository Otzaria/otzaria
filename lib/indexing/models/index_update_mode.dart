import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// מצב עדכון אינדקס החיפוש האוטומטי.
enum IndexUpdateMode {
  /// כל הספרים, כולל ספרים אישיים.
  all('all'),

  /// הספרייה בלבד — ספרים אישיים אינם מאונדקסים ומוסרים מהאינדקס.
  libraryOnly('library-only'),

  /// אין עדכון אוטומטי.
  off('off');

  const IndexUpdateMode(this.storageValue);

  final String storageValue;

  bool get isAutomatic => this != off;

  bool get indexesPersonalBooks => this != libraryOnly;

  /// האם [book] נכנס לאינדקס במצב זה.
  bool admits(Book book) => indexesPersonalBooks || !book.source.isUser;

  /// המפתח הבוליאני הישן קובע הפעלה/כיבוי, כדי שגרסה ישנה שמשנה רק אותו
  /// תיקרא נכון; [stored] רק מבחין בין "כל הספרים" ל"בלי ספרים אישיים".
  static IndexUpdateMode resolve({
    required bool legacyEnabled,
    String? stored,
  }) {
    if (!legacyEnabled) return off;
    return stored == libraryOnly.storageValue ? libraryOnly : all;
  }

  /// המצב השמור. בלי הגדרות מאותחלות (בדיקות) — [all], ההתנהגות הקודמת.
  static IndexUpdateMode readStored() {
    if (!Settings.isInitialized) return all;
    return resolve(
      legacyEnabled:
          Settings.getValue<bool>(SettingsRepository.keyAutoUpdateIndex) ??
          true,
      stored: Settings.getValue<String>(SettingsRepository.keyIndexUpdateMode),
    );
  }
}

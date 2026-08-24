import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// מדיניות ה-blocklist של `settings.read`: כל הגדרה קריאה, למעט סודות, נתיבים,
/// פרטים מזהים ותוכן אישי. הבדיקה מגנה על שני הכיוונים — שסוד לא ייפתח, ושמפתח
/// תצוגה חדש לא ייחסם בטעות (זו כל מטרת המעבר מ-allowlist).
void main() {
  group('חסום', () {
    const secrets = [
      SettingsRepository.keyProtectedModePasswordHash,
      SettingsRepository.keyGoogleCalendarClientSecret,
      SettingsRepository.keyGoogleCalendarCredentialsJson,
      SettingsRepository.keyGoogleCalendarClientId,
      SettingsRepository.keyErrorReportSenderEmail,
    ];

    const paths = [
      SettingsRepository.keyDbEffectivePath,
      SettingsRepository.keyLibraryPath,
      SettingsRepository.keyIndexPath,
      SettingsRepository.keyBackupPath,
      SettingsRepository.keyDatabasesPath,
      SettingsRepository.keyHebrewBooksPath,
      SettingsRepository.keyAndroidLibraryRoot,
      SettingsRepository.keyCustomFolders,
      SettingsRepository.keyLibraryFolderName,
    ];

    const personal = [
      'key-bookmarks',
      'key-tabs',
      'key-current-tab',
      'key-workspaces',
      'key-current-workspace-id',
      'key-saved-alternative-words',
      'key-plugin-search-selections',
      'sz:tracked_books',
      'sz:progress_by_id',
      SettingsRepository.keyCalendarEvents,
      SettingsRepository.keyCalendarEventNotificationIds,
      SettingsRepository.keyProtectedModeEnabled,
      SettingsRepository.keyGoogleCalendarEnabled,
      SettingsRepository.keyGoogleCalendarSelectedIds,
    ];

    for (final key in [...secrets, ...paths, ...personal]) {
      test(
        key,
        () => expect(PluginSettingsAccessPolicy.isReadable(key), isFalse),
      );
    }

    test('מפתח היפותטי חדש שנושא סוד או נתיב חסום מלידתו', () {
      for (final key in const [
        'key-some-new-api-key',
        'key-new-feature-token',
        'key-future-export-path',
        'key-something-password',
        'key-drive-credential-blob',
        'key-user-email-alias',
        'key-new-folder-list',
      ]) {
        expect(
          PluginSettingsAccessPolicy.isReadable(key),
          isFalse,
          reason: key,
        );
      }
    });

    test('מפתח ריק חסום', () {
      expect(PluginSettingsAccessPolicy.isReadable(''), isFalse);
      expect(PluginSettingsAccessPolicy.isReadable('   '), isFalse);
    });

    test('אותיות גדולות אינן עוקפות את החסימה', () {
      expect(
        PluginSettingsAccessPolicy.isReadable('key-LIBRARY-PATH'),
        isFalse,
      );
    });
  });

  group('קריא', () {
    const readable = [
      SettingsRepository.keyDarkMode,
      SettingsRepository.keyFollowSystemTheme,
      SettingsRepository.keySwatchColor,
      SettingsRepository.keyDarkSwatchColor,
      SettingsRepository.keyFontSize,
      SettingsRepository.keyFontFamily,
      SettingsRepository.keyCommentatorsFontFamily,
      SettingsRepository.keyCommentatorsFontSize,
      SettingsRepository.keyLineHeight,
      SettingsRepository.keySelectedCity,
      SettingsRepository.keyCalendarType,
      SettingsRepository.keySettingsLanguage,
      SettingsRepository.keyShowTeamim,
      SettingsRepository.keyDefaultNikud,
      SettingsRepository.keyRemoveNikudFromTanach,
      SettingsRepository.keyReplaceHolyNames,
      SettingsRepository.keyLibraryViewMode,
      SettingsRepository.keyCopyWithHeaders,
      SettingsRepository.keyCopyHeaderFormat,
    ];

    // כל מה שהיה ברשימת ההיתר עד 0.9.96 חייב להישאר קריא — למעט נתיב
    // ספרי HebrewBooks, שנחסם ביודעין עם כל הנתיבים.
    for (final key in readable) {
      test(
        key,
        () => expect(PluginSettingsAccessPolicy.isReadable(key), isTrue),
      );
    }

    test('העדפת תצוגה שלא הייתה ברשימת ההיתר נפתחה כעת', () {
      for (final key in const [
        SettingsRepository.keyTextMaxWidth,
        SettingsRepository.keyFontBold,
        SettingsRepository.keyCommentatorsFontBold,
        SettingsRepository.keyDefaultRemovePunctuation,
        SettingsRepository.keyContinuousReadingMode,
        SettingsRepository.keyPageShapeBottomFont,
        SettingsRepository.keyCompactMenuMode,
        SettingsRepository.keyReadingTabsPlacement,
        SettingsRepository.keyOfflineMode,
      ]) {
        expect(PluginSettingsAccessPolicy.isReadable(key), isTrue, reason: key);
      }
    });

    // משפחות שנבנות בזמן ריצה: שם הספר/הקטגוריה או מזהה תוסף אחר הוא חלק
    // מהמפתח, ולכן קריאתן מדליפה מה המשתמש לומד או אילו תוספים מותקנים.
    test('מפתחות דינמיים פר-ספר ופר-תוסף חסומים', () {
      for (final key in const [
        'page_shape_book_ברכות',
        'page_shape_highlight_ברכות',
        'page_shape_visibility_ברכות',
        'page_shape_use_book_settings_ברכות',
        'page_shape_view_mode_ברכות',
        'page_shape_category_תלמוד בבלי',
        'key-shortcut-open-plugin-some.other.plugin',
      ]) {
        expect(
          PluginSettingsAccessPolicy.isBlocked(key),
          isTrue,
          reason: key,
        );
      }
    });

    test('העדפת התצוגה הגלובלית של צורת הדף נשארת קריאה', () {
      for (final key in const [
        'page_shape_global_visibility_left',
        'page_shape_global_visibility_bottomRight',
      ]) {
        expect(PluginSettingsAccessPolicy.isReadable(key), isTrue, reason: key);
      }
    });
  });
}

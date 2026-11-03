import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// q9 Q6 = C: רק AppScopeProviders מחבר את קובץ ההגדרות (Hive) ל־SettingsBloc.
/// בלי החיבור, כתיבה שלא עוברת דרך הבלוק (הקורא, חלון אחר, שירות הגיבוי)
/// משאירה ערך ישן בלשוניות ההגדרות.
///
/// `test` ולא `testWidgets`: הכתיבות לקובץ אמיתיות, ובאזור הזמן המדומה של
/// testWidgets הן לא מסתיימות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app_scope_settings_sync_');
    AppPaths.debugOverrideDataRootPath(root.path);
    Hive.init(root.path);
    await Settings.init(cacheProvider: HiveCache());
    // בלי כתיבת ברירות המחדל של LoadSettings, שהייתה ממשיכה אחרי סגירת Hive.
    await Settings.setValue<bool>('settings_initialized', true);
  });

  tearDown(() async {
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows: הקובץ עוד נעול רגע אחרי הסגירה; תיקייה זמנית.
    }
  });

  test(
    'כתיבה ישירה לקובץ ההגדרות מגיעה ל־SettingsBloc של היקף התהליך',
    () async {
      final bloc = AppScopeProviders.createSettingsBloc(SettingsRepository());
      // LoadSettings (בלי כתיבות) רץ ברקע.
      await pumpEventQueue();
      expect(bloc.state.splitedView, isTrue);
      expect(bloc.state.backupIncludesAllSections, isTrue);

      // הקורא (TextBookBloc) ושירות הגיבוי כותבים ישר ל־Settings.
      await Settings.setValue<bool>(SettingsRepository.keySplitedView, false);
      await Settings.setValue<bool>(SettingsRepository.keyBackupNotes, false);
      // הגדרת הספרייה כותבת את הנתיב ישר ל־Settings (q10 שאלה 21).
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        'C:/otzaria/books',
      );
      await pumpEventQueue();

      expect(bloc.state.splitedView, isFalse);
      expect(
        bloc.state.backupIncludes(SettingsRepository.keyBackupNotes),
        isFalse,
      );
      expect(bloc.state.backupIncludesAllSections, isFalse);
      expect(bloc.state.libraryPath, 'C:/otzaria/books');
      await bloc.close();
    },
  );

  test('בלי Hive פתוח הזרם ריק', () async {
    await Hive.close();
    expect(await HiveCache.changedKeys().isEmpty, isTrue);
  });
}

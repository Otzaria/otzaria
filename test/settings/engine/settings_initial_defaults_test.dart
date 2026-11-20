import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/search/settings_search_index.dart';
import 'package:otzaria/settings/tabs/design_settings_tab.dart';

import '../../helpers/memory_settings_cache.dart';

/// issue #3512: ברירות המחדל של [SettingsState.initial] הן גם קו הבסיס שמאזין
/// התוספים ב-MainWindowScreen משווה אליו. ערך ששונה מברירת המחדל שבאחסון נשלח
/// לתוספים כ-settings.changed בלי שהמשתמש שינה דבר.
void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('גודל הגופן ההתחלתי זהה לברירת המחדל שבאחסון', () async {
    final repository = SettingsRepository();
    final bloc = SettingsBloc(
      repository: repository,
      initialSettings: repository.readSettings(),
      ensureFontLoaded: (_) async {},
    );
    addTearDown(bloc.close);

    final initial = SettingsState.initial();
    expect(initial.fontSize, bloc.state.fontSize);
    expect(initial.searchResultsFontSize, bloc.state.searchResultsFontSize);
  });

  test('כותרת תצוגת ספר ב-PDF מופרדת במקף', () {
    final entry = DesignSettingsTab.searchEntries.firstWhere(
      (e) => e.id == 'design.pdf.book_view',
    );
    expect(entry.title, 'תצוגת ספר ב-PDF');
  });

  test('הגדרת תצוגת ספר נמצאת גם בחיפוש הכותרת בלי המקף', () {
    for (final language in [
      SettingsLanguage.source,
      SettingsLanguage.english,
    ]) {
      expect(
        SettingsSearchIndex.search(
          'תצוגת ספר בPDF',
          language: language,
        ).map((entry) => entry.id),
        contains('design.pdf.book_view'),
      );
    }
  });
}

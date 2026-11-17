import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/saved_alternatives_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  const key = 'key-saved-alternative-words';

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('עדכון באחסון מחליף מיד את החלופות שכבר נקראו', () async {
    await Settings.setValue(key, '{"שלום":["שלם"]}');
    expect(SavedAlternativesStore.alternativesFor('שלום'), ['שלם']);
    await Settings.setValue(key, '{"שלום":["שלומ"]}');
    expect(SavedAlternativesStore.alternativesFor(' שלום '), ['שלומ']);
    await Settings.setValue<String?>(key, null);
    expect(SavedAlternativesStore.loadAll(), isEmpty);
    await Settings.setValue(key, '{"אחר":["חלופה"]}');
    expect(SavedAlternativesStore.alternativesFor('שלום'), isEmpty);
    expect(SavedAlternativesStore.alternativesFor('אחר'), ['חלופה']);
  });

  test('תוצאות ציבוריות אינן משנות את התוכן הממוטמן', () async {
    await Settings.setValue(key, '{"שלום":["שלם"],"עולם":["עלם"]}');
    final all = SavedAlternativesStore.loadAll();
    final alternatives = SavedAlternativesStore.alternativesFor('שלום');
    all['שלום']!.add('שינוי');
    all.remove('עולם');
    all['חדש'] = ['מילה'];
    alternatives.clear();

    expect(SavedAlternativesStore.loadAll(), {
      'שלום': ['שלם'],
      'עולם': ['עלם'],
    });
    expect(SavedAlternativesStore.alternativesFor('שלום'), ['שלם']);
  });

  test('הוספה והסרה משמרות את כל המילים אחרי קריאה מהמטמון', () async {
    await Settings.setValue(key, '{"שלום":["שלם"],"עולם":["עלם"]}');
    SavedAlternativesStore.loadAll();
    SavedAlternativesStore.addAlternative(' שלום ', 'שלומ');
    SavedAlternativesStore.addAlternative('שלום', 'שלומ');
    SavedAlternativesStore.addAlternative('שלום', 'שלום');
    expect(SavedAlternativesStore.alternativesFor('שלום'), ['שלם', 'שלומ']);

    SavedAlternativesStore.removeAlternative('שלום', 'שלם');
    expect(SavedAlternativesStore.alternativesFor('שלום'), ['שלומ']);
    SavedAlternativesStore.removeAlternative('שלום', 'שלומ');
    expect(SavedAlternativesStore.loadAll(), {
      'עולם': ['עלם'],
    });
  });

  test('ערכים לא תקינים נשארים ריקים ועדכון תקין מתאושש מהם', () async {
    for (final raw in ['', '{', '[]', 'null', '7']) {
      await Settings.setValue(key, raw);
      expect(SavedAlternativesStore.loadAll(), isEmpty, reason: raw);
      expect(SavedAlternativesStore.alternativesFor('שלום'), isEmpty);
    }
    await Settings.setValue(key, '{"שלום":["שלם",7,null],"אחר":false}');
    expect(SavedAlternativesStore.loadAll(), {
      'שלום': ['שלם', '7', 'null'],
    });
  });

  test('אתחול אחסון חדש אינו משאיר חלופות מהספק הקודם', () async {
    await Settings.setValue(key, '{"שלום":["שלם"]}');
    expect(SavedAlternativesStore.alternativesFor('שלום'), ['שלם']);
    await Settings.init(cacheProvider: MemoryCacheProvider());
    expect(SavedAlternativesStore.loadAll(), isEmpty);
  });
}

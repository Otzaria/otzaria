import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ready = await tryInitSearchEngine();

  test('כל נתוני הרחבות החיפוש נשמרים בזמן העשרת כלי המילון', () async {
    final source = await rootBundle.load('assets/search_acronyms.json');
    final bytes = source.buffer.asUint8List(
      source.offsetInBytes,
      source.lengthInBytes,
    );
    // שינוי הרחבות החיפוש דורש אימות נפרד של תוצאות וביצועים בשני הכיוונים.
    expect(
      sha256.convert(bytes).toString(),
      'bea6b34a6dce8fef7cbfa00509a75bbd4557b8b33af8b82890c4bfe007db1633',
    );
    final search = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(search.length, 13165);
    expect(
      search.values.fold<int>(
        0,
        (n, meanings) => n + (meanings as List).length,
      ),
      29126,
    );
    final dictionary =
        jsonDecode(await rootBundle.loadString('assets/Acronyms.json'))
            as Map<String, dynamic>;
    expect(dictionary.length, greaterThan(search.length));
  });

  test('המילון המורחב אינו דוחק פענוחים מהחיפוש המלא', () async {
    final root = await Directory.systemTemp.createTemp('acronym_search_');
    AppPaths.debugOverrideDataRootPath('${root.path}/data');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue(
      SettingsRepository.keyIndexPath,
      '${root.path}/index',
    );
    final provider = TantivyDataProvider.instance;
    addTearDown(() async {
      await provider.dispose();
      AppPaths.debugOverrideDataRootPath(null);
      await Settings.clearCache();
      await root.delete(recursive: true);
    });
    final engine = await provider.engine;
    expect(
      await File(
        '${root.path}/data/dictionaries/search_acronyms.json',
      ).readAsBytes(),
      await File('assets/search_acronyms.json').readAsBytes(),
    );
    const lines = [
      'אביו ואמו',
      'אלוהינו ואלוהי אבותינו',
      'אופן אחר',
      'או"א',
      'איש ואשה',
      'בן המחבר',
      'בה"מ',
      'מקח וממכר',
      'מעלה ומטה',
      'מו"מ',
    ];
    for (var i = 0; i < lines.length; i++) {
      await engine.addDocument(
        ordinal: i,
        title: 'ספר',
        reference: 'שורה $i',
        topics: '/test/acronyms',
        text: lines[i],
        segment: BigInt.from(i),
        isPdf: false,
        filePath: 'id:1',
      );
    }
    await engine.commit();
    Future<List<int>> find(String query) async {
      final result = await engine.searchAdvanced(
        query: query,
        negativeQuery: '',
        facets: ['/test/acronyms'],
        limit: 100,
        offset: 0,
        distance: 0,
        negativeDistance: 0,
        customSpacing: {},
        negativeCustomSpacing: {},
        alternativeWords: {},
        negativeAlternativeWords: {},
        searchOptions: {
          '${query}_0': {'ראשי תיבות': true},
        },
        negativeSearchOptions: {},
        order: ResultsOrder.catalogue,
        matchNikud: false,
        matchTaamim: false,
        scope: SearchScope.wordDistance,
        negativeScope: SearchScope.wordDistance,
      );
      return result.map((r) => r.segment.toInt()).toList()..sort();
    }

    expect(await find('או"א'), [0, 1, 2, 3]);
    expect(await find('בה"מ'), [5, 6]);
    expect(await find('מו"מ'), [7, 8, 9]);
  }, skip: ready ? false : searchEngineSkipReason);
}

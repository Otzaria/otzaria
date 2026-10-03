import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/in_book_advanced_search_dialog.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('the dialog tab edits the restored per-word options', () {
    final searchOptions = {
      'שלום_0': {'קידומות': true},
    };
    final alternativeWords = {
      0: ['שלם'],
    };
    final spacingValues = {'שלום_0': '2'};

    final tab = createInBookSearchDialogTab(
      query: 'שלום עולם',
      searchMode: SearchMode.advanced,
      distance: 3,
      matchPolicy: SearchMatchPolicy.standard,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
    );
    addTearDown(tab.dispose);

    expect(tab.useGlobalSearchOptions.value, isFalse);
    expect(tab.queryController.text, 'שלום עולם');
    expect(tab.searchOptions, searchOptions);
    expect(tab.alternativeWords, alternativeWords);
    expect(tab.spacingValues, spacingValues);
  });

  test('editing the dialog tab leaves the source settings unchanged', () {
    final searchOptions = {
      'שלום_0': {'קידומות': true},
    };
    final alternativeWords = {
      0: ['שלם'],
    };

    final tab = createInBookSearchDialogTab(
      query: 'שלום',
      searchMode: SearchMode.advanced,
      distance: 0,
      matchPolicy: SearchMatchPolicy.standard,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: const {},
    );
    addTearDown(tab.dispose);

    tab.searchOptions['שלום_0']!['סיומות'] = true;
    tab.alternativeWords[0]!.add('שולם');

    expect(searchOptions, {
      'שלום_0': {'קידומות': true},
    });
    expect(alternativeWords, {
      0: ['שלם'],
    });
  });
}

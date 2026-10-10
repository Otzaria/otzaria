import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/in_book_advanced_search_dialog.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

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

  test('ברירת המחדל השמורה מסומנת בחלון גם לפני שהוקלדה שאילתה', () {
    final tab = createInBookSearchDialogTab(
      query: '',
      searchMode: SearchMode.exact,
      distance: 0,
      matchPolicy: SearchMatchPolicy.standard,
      searchOptions: const {},
      alternativeWords: const {},
      spacingValues: const {},
      optionsForEveryWord: const {'קידומות דקדוקיות': true},
    );
    addTearDown(tab.dispose);

    expect(tab.useGlobalSearchOptions.value, isTrue);
    expect(tab.globalSearchOptions, {'קידומות דקדוקיות': true});
  });

  for (final words in [
    ['שלום', 'עולם'],
    ['שלום', 'שלום'],
    ['שָׁלוֹם', 'שָׁלוֹם'],
  ]) {
    test('אפשרויות אחידות בחיפוש מדויק חוזרות למצב גלובלי: $words', () {
      final options = {
        for (var i = 0; i < words.length; i++)
          '${words[i]}_$i': {'קידומות דקדוקיות': true},
      };
      final tab = createInBookSearchDialogTab(
        query: words.join(' '),
        searchMode: SearchMode.exact,
        distance: 0,
        matchPolicy: SearchMatchPolicy.standard,
        searchOptions: options,
        alternativeWords: const {},
        spacingValues: const {},
      );
      addTearDown(tab.dispose);

      expect(tab.useGlobalSearchOptions.value, isTrue);
      expect(tab.globalSearchOptions, {'קידומות דקדוקיות': true});
      expect(tab.effectiveSearchOptions(), options);
    }, skip: !engineReady);
  }

  for (final options in [
    {
      'שלום_0': {'קידומות דקדוקיות': true},
    },
    {
      'שלום_0': {'קידומות דקדוקיות': true},
      'עולם_1': {'סיומות דקדוקיות': true},
    },
    {
      'ישן_0': {'קידומות דקדוקיות': true},
      'עולם_1': {'קידומות דקדוקיות': true},
    },
  ]) {
    test('חיפוש מדויק שומר אפשרויות פר-מילה שאינן גלובליות: $options', () {
      final tab = createInBookSearchDialogTab(
        query: 'שלום עולם',
        searchMode: SearchMode.exact,
        distance: 0,
        matchPolicy: SearchMatchPolicy.standard,
        searchOptions: options,
        alternativeWords: const {},
        spacingValues: const {},
      );
      addTearDown(tab.dispose);

      expect(tab.useGlobalSearchOptions.value, isFalse);
      expect(tab.globalSearchOptions, isEmpty);
      expect(tab.effectiveSearchOptions(), options);
    }, skip: !engineReady);
  }

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

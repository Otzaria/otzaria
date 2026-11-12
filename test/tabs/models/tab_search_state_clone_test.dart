import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

/// שכפול טאב (`OpenedTab.from`) משמש לשחזור טאב שנסגר, לשכפול ולמעבר בין
/// שולחנות עבודה. בלי קונפיגורציית החיפוש, החיפוש שבספר המשוחזר חוזר למסלול
/// המחרוזת הרצופה ומציג "אין תוצאות" על תוצאה שהחיפוש הגלובלי מצא.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  const policy = SearchMatchPolicy(
    proximityScope: SearchScope.sameParagraph,
    wordMatchMode: WordMatchMode.atLeast,
    wordMatchCount: 3,
  );

  for (final wordDefaults in [
    null,
    const {'קידומות דקדוקיות': true},
  ]) {
    test(
      'snapshot תבנית ($wordDefaults) אינו קורא העדפות חדשות בשכפול/שחזור',
      () {
        final template = InBookSearchTemplate(
          wordDefaults: wordDefaults,
          requestedPolicy: const SearchMatchPolicy(anyOrder: true),
        );
        final text = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 0,
          searchText: 'ממון',
          searchTemplate: template,
        );
        final pdf = PdfBookTab(
          book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
          pageNumber: 1,
          searchText: 'ממון',
          searchTemplate: template,
          centerSearchMatchPage: 5,
        );
        SearchDefaults.saveExactDefaults(const {'תחיליות': true});
        SearchDefaults.saveAnyOrderDefault(false);
        addTearDown(() => SearchDefaults.saveExactDefaults(const {}));
        final textClone = OpenedTab.from(text) as TextBookTab;
        final pdfClone = OpenedTab.from(pdf) as PdfBookTab;
        final textRestored = TextBookTab.fromJson(text.toJson());
        final pdfRestored = PdfBookTab.fromJson(pdf.toJson());
        for (final tab in [
          text,
          pdf,
          textClone,
          pdfClone,
          textRestored,
          pdfRestored,
        ]) {
          addTearDown(tab.dispose);
        }
        expect(textClone.searchTemplate, template);
        expect(
          (textClone.blocState as TextBookInitial).searchTemplate,
          template,
        );
        expect(textRestored.searchTemplate, template);
        expect(pdfClone.searchTemplate, template);
        expect(pdfRestored.searchTemplate, template);
        expect(pdfClone.takeCenterSearchMatchPage(), isNull);
        expect(pdfRestored.takeCenterSearchMatchPage(), isNull);
        expect(pdf.takeCenterSearchMatchPage(), 5);
        expect(textRestored.searchTemplate!.requestedPolicy.anyOrder, isTrue);
      },
    );
  }

  for (final origin in InBookSearchOrigin.values) {
    test('מקור $origin נשמר בשכפול ובשחזור של טקסט ו-PDF', () {
      final text = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 0,
        searchText: 'תדע זרעך',
        searchDistance: 3,
        searchOrigin: origin,
      );
      final pdf = PdfBookTab(
        book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
        pageNumber: 1,
        searchText: 'תדע זרעך',
        searchDistance: 3,
        searchOrigin: origin,
      );
      final textClone = OpenedTab.from(text) as TextBookTab;
      final pdfClone = OpenedTab.from(pdf) as PdfBookTab;
      final textRestored = TextBookTab.fromJson(text.toJson());
      final pdfRestored = PdfBookTab.fromJson(pdf.toJson());
      for (final tab in [
        text,
        pdf,
        textClone,
        pdfClone,
        textRestored,
        pdfRestored,
      ]) {
        addTearDown(tab.dispose);
      }
      expect(textClone.searchOrigin, origin);
      expect((textClone.bloc.state as TextBookInitial).searchOrigin, origin);
      expect(textRestored.searchOrigin, origin);
      expect(pdfClone.searchOrigin, origin);
      expect(pdfRestored.searchOrigin, origin);
      expect(textRestored.searchDistance, 3);
      expect(pdfRestored.searchDistance, 3);
    });
  }

  test('שמירה ישנה או מקור לא מוכר אינם מסומנים כתוצאה גלובלית', () {
    for (final value in [null, 'futureValue', 42]) {
      final restored = ReadingTabSearchState.fromJson({
        'searchText': 'תדע זרעך',
        'searchDistance': 3,
        'searchOrigin': ?value,
      });
      expect(restored.searchOrigin, InBookSearchOrigin.inBook);
      expect(restored.searchDistance, 3);
    }
  });

  test('שכפול טאב טקסט שומר את כל קונפיגורציית החיפוש', () {
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 389,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(clone.searchText, 'תדע זרעך');
    expect(clone.searchMode, SearchMode.advanced);
    expect(clone.searchDistance, 3);
    expect(clone.matchPolicy, policy);
    expect(clone.searchOptions, original.searchOptions);
    expect(clone.alternativeWords, original.alternativeWords);
    expect(clone.spacingValues, original.spacingValues);
  });

  test('שכפול טאב PDF שומר את כל קונפיגורציית החיפוש', () {
    final original = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 5,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as PdfBookTab;
    addTearDown(clone.dispose);

    expect(clone.searchText, 'תדע זרעך');
    expect(clone.searchMode, SearchMode.advanced);
    expect(clone.searchDistance, 3);
    expect(clone.matchPolicy, policy);
    expect(clone.searchOptions, original.searchOptions);
    expect(clone.alternativeWords, original.alternativeWords);
    expect(clone.spacingValues, original.spacingValues);
  });

  test('תצורה נכנסת לטאב PDF בלי חלונית מחוברת נכתבת גם לשדה החיפוש', () {
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 1,
      searchText: 'תדע',
    );
    addTearDown(tab.dispose);

    tab.applyIncomingSearchConfiguration(
      ReadingTabSearchState(
        searchText: 'תדע זרעך',
        searchOptions: const {
          'תדע_0': {'ראשי תיבות': true},
        },
        searchMode: SearchMode.advanced,
        searchDistance: 3,
        matchPolicy: policy,
      ),
    );

    expect(tab.searchText, 'תדע זרעך');
    expect(tab.searchController.text, 'תדע זרעך');
    expect(tab.searchMode, SearchMode.advanced);
    expect(tab.searchDistance, 3);
    expect(tab.matchPolicy, policy);
    expect(tab.searchOptions, {
      'תדע_0': {'ראשי תיבות': true},
    });
    expect(tab.incomingSearchConfiguration.value, isNotNull);
  });

  test('חלונית מחוברת שקלטה את התצורה מונעת כתיבה לשדה החיפוש', () {
    // כתיבה לשדה החיפוש הייתה מפעילה את ה-listener של החלונית עם התצורה
    // הישנה, ומריצה את השאילתה החדשה במסלול הפשוט.
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 1,
      searchText: 'תדע',
    );
    addTearDown(tab.dispose);

    void consume() {
      if (tab.incomingSearchConfiguration.value == null) return;
      tab.incomingSearchConfiguration.value = null;
    }

    tab.incomingSearchConfiguration.addListener(consume);
    addTearDown(() => tab.incomingSearchConfiguration.removeListener(consume));

    tab.applyIncomingSearchConfiguration(
      const ReadingTabSearchState(searchText: 'תדע זרעך', searchDistance: 3),
    );

    expect(tab.searchDistance, 3);
    expect(tab.searchController.text, 'תדע');
  });

  test('JSON round-trip של טאב טקסט שומר את כל קונפיגורציית החיפוש', () {
    // שמירת שולחן עבודה ויציאה מהאפליקציה: בלי השימור, הספר נפתח מחדש
    // כחיפוש מחרוזת רצופה והחלונית הציגה "אין תוצאות".
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 389,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final restored = TextBookTab.fromJson(original.toJson());
    addTearDown(restored.dispose);

    expect(restored.searchText, 'תדע זרעך');
    expect(restored.searchMode, SearchMode.advanced);
    expect(restored.searchDistance, 3);
    expect(restored.matchPolicy, policy);
    expect(restored.searchOptions, original.searchOptions);
    expect(restored.alternativeWords, original.alternativeWords);
    expect(restored.spacingValues, original.spacingValues);
  });

  test('JSON round-trip של טאב PDF שומר את כל קונפיגורציית החיפוש', () {
    final original = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 5,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final restored = PdfBookTab.fromJson(original.toJson());
    addTearDown(restored.dispose);

    expect(restored.searchText, 'תדע זרעך');
    expect(restored.searchMode, SearchMode.advanced);
    expect(restored.searchDistance, 3);
    expect(restored.matchPolicy, policy);
    expect(restored.searchOptions, original.searchOptions);
    expect(restored.alternativeWords, original.alternativeWords);
    expect(restored.spacingValues, original.spacingValues);
  });

  test('טאב בלי חיפוש נשמר בלי שדות חיפוש, ונטען כברירת מחדל', () {
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
    );
    addTearDown(original.dispose);

    final json = original.toJson();
    expect(json.containsKey('searchText'), isFalse);
    expect(json.containsKey('searchMode'), isFalse);

    final restored = TextBookTab.fromJson(json);
    addTearDown(restored.dispose);
    expect(restored.searchText, isEmpty);
    expect(restored.searchMode, SearchMode.exact);
    expect(restored.matchPolicy, SearchMatchPolicy.standard);
  });

  test('שמירה ישנה (בלי שדות חיפוש) נטענת בברירות המחדל', () {
    // תאימות לאחור: קבצי טאבים ושולחנות עבודה קיימים אינם מכילים את השדות.
    final restored = TextBookTab.fromJson({
      'title': 'בראשית',
      'initalIndex': 5,
      'commentators': <String>[],
      'showLeftPane': false,
      'searchMode': 'no-such-mode',
      'searchMatchPolicy': 'not-a-map',
    });
    addTearDown(restored.dispose);

    expect(restored.searchText, isEmpty);
    expect(restored.searchMode, SearchMode.exact);
    expect(restored.matchPolicy, SearchMatchPolicy.standard);
  });

  test('שכפול ושמירה מעדיפים את מקור ההגדרות המעודכן בבלוק', () {
    final state = _loadedState(
      searchText: 'תדע זרעך',
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    final bloc = StubTextBookBloc(state);
    final original = TextBookTab(
      book: state.book,
      index: 0,
      searchText: 'תדע זרעך',
      searchOrigin: InBookSearchOrigin.globalResult,
      blocOverride: bloc,
    );
    final clone = OpenedTab.from(original) as TextBookTab;
    final restored = TextBookTab.fromJson(original.toJson());
    for (final tab in [original, clone, restored]) {
      addTearDown(tab.dispose);
    }
    expect(clone.searchOrigin, InBookSearchOrigin.inBook);
    expect(restored.searchOrigin, InBookSearchOrigin.inBook);
    expect(clone.searchDistance, 3);
    expect(restored.searchDistance, 3);
  });

  test('שכפול טאב טקסט מעדיף את מצב החיפוש המעודכן מה-BLoC', () {
    // המשתמש שינה את החיפוש בתוך הספר (חיפוש מתקדם מהחלונית): שדות הטאב
    // נשארים על הערכים שאיתם נפתח, וה-state הוא המצב האמיתי.
    final bloc = StubTextBookBloc(
      _loadedState(
        searchText: 'תדע זרעך',
        searchMode: SearchMode.advanced,
        searchDistance: 3,
        matchPolicy: policy,
      ),
    );
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
      searchText: 'ישן',
      blocOverride: bloc,
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(clone.searchText, 'תדע זרעך');
    expect(clone.searchMode, SearchMode.advanced);
    expect(clone.searchDistance, 3);
    expect(clone.matchPolicy, policy);
  });
}

TextBookLoaded _loadedState({
  required String searchText,
  required SearchMode searchMode,
  required int searchDistance,
  required SearchMatchPolicy matchPolicy,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'בראשית'),
    showLeftPane: true,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: searchText,
    searchMode: searchMode,
    searchDistance: searchDistance,
    matchPolicy: matchPolicy,
  );
}

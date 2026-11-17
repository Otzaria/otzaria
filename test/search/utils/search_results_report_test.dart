import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/utils/search_results_report.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_state.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchResult, SemanticResultSource, TextStatus;

TabsState _tabs(OpenedTab? tab) => TabsState(
  tabs: [?tab],
  currentTabIndex: 0,
);

SearchResult _lexical(
  String filePath,
  String text, {
  TextStatus status = TextStatus.ok,
  int segment = 7,
  bool isPdf = false,
}) => SearchResult(
  title: 'ספר $filePath',
  reference: 'ספר, פרק א',
  text: text,
  id: BigInt.from(1),
  segment: BigInt.from(segment),
  isPdf: isPdf,
  filePath: filePath,
  mergedCount: 1,
  merged: const [],
  textStatus: status,
  continuesToNextLine: false,
);

SemanticResultItem _semantic(
  String filePath, {
  required SemanticResultSource source,
  required bool highlighted,
  TextStatus status = TextStatus.ok,
}) => SemanticResultItem(
  title: 'ספר $filePath',
  reference: 'ספר, פרק א',
  snippetHtml: 'בית שער',
  isHighlighted: highlighted,
  textStatus: status,
  id: BigInt.from(1),
  segment: 3,
  isPdf: false,
  filePath: filePath,
  source: source,
  fusedScore: 1,
);

void main() {
  test('חיפוש רגיל: סופר הדגשות ומצבי טקסט ומפרט תוצאה שלא הודגשה', () {
    final report = describeLexicalResults(
      SearchState(
        totalResults: 40,
        results: [
          _lexical('id:1', 'ואחד <font color=red>בית</font> שער'),
          _lexical('id:2', 'לקמיה בית שער', status: TextStatus.stale),
          _lexical('uid:9', 'בית שער פרטי', segment: 4),
        ],
      ),
    );

    expect(report['kind'], 'lexical');
    expect(report['total'], 40);
    expect(report['shown'], 3);
    expect(report['textStatus'], {'ok': 2, 'stale': 1});
    expect(report['unhighlighted'], 2);
    expect(report['unhighlightedSamples'], [
      {
        'book': 'id:2',
        'title': 'ספר id:2',
        'segment': 7,
        'textStatus': 'stale',
      },
      {'book': 'user', 'segment': 4, 'textStatus': 'ok'},
    ]);
    expect(report.toString(), isNot(contains('בית שער פרטי')));
  });

  test('חיפוש חכם: התאמה לפי עניין בלבד אינה נספרת כחסרת הדגשה', () {
    final report = describeSemanticResults(
      SemanticResultsState(
        status: SemanticResultsStatus.loaded,
        items: [
          _semantic(
            'id:1',
            source: SemanticResultSource.semantic,
            highlighted: false,
          ),
          _semantic(
            'id:2',
            source: SemanticResultSource.lexical,
            highlighted: false,
            status: TextStatus.stale,
          ),
          _semantic(
            'ext:5',
            source: SemanticResultSource.both,
            highlighted: true,
          ),
        ],
      ),
    );

    expect(report['status'], 'loaded');
    expect(report['bySource'], {'semantic': 1, 'lexical': 1, 'both': 1});
    expect(report['unhighlighted'], 1);
    expect(report['unhighlightedSamples'], [
      {
        'book': 'id:2',
        'title': 'ספר id:2',
        'segment': 3,
        'textStatus': 'stale',
        'source': 'lexical',
      },
    ]);
  });

  test('נתיב PDF וספר מצורף מזוהים רק בסוגם', () {
    const pdfPath = r'C:\Users\Moshe\ספרים\פרטי.pdf';
    final report = describeLexicalResults(
      SearchState(
        results: [
          _lexical(pdfPath, 'בלי הדגשה', isPdf: true),
          _lexical('db:my-lib:12', 'בלי הדגשה'),
        ],
      ),
    );

    expect(report['unhighlightedSamples'], [
      {'book': 'path', 'segment': 7, 'textStatus': 'ok', 'pdf': true},
      {'book': 'attached', 'segment': 7, 'textStatus': 'ok'},
    ]);
    expect(report.toString(), isNot(contains('Moshe')));
    expect(report.toString(), isNot(contains('my-lib')));
  });

  test('רק לשונית חיפוש מתוארת, ובלוק החיפוש החכם לא נוצר בשבילה', () {
    expect(describeSearchResults(_tabs(null)), isNull);
    expect(
      describeSearchResults(_tabs(ToolTab(toolId: 'x', title: 'x'))),
      isNull,
    );

    final lexical = SearchingTab('חיפוש', null);
    addTearDown(lexical.dispose);
    expect(describeSearchResults(_tabs(lexical))?['kind'], 'lexical');

    final semantic = SemanticSearchTab(
      options: const SemanticQueryOptions(query: 'בית שער'),
    );
    addTearDown(semantic.dispose);
    expect(describeSearchResults(_tabs(semantic)), {
      'kind': 'semantic',
      'status': 'notStarted',
    });
    expect(semantic.createdResultsBloc, isNull);
  });

  test('הדוגמאות מוגבלות', () {
    final report = describeLexicalResults(
      SearchState(
        results: [
          for (var i = 0; i < maxUnhighlightedSamples + 5; i++)
            _lexical('id:$i', 'בלי הדגשה'),
        ],
      ),
    );

    expect(report['unhighlighted'], maxUnhighlightedSamples + 5);
    expect(
      report['unhighlightedSamples'] as List,
      hasLength(maxUnhighlightedSamples),
    );
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

/// כרטיסיית תוצאות של החיפוש הסמנטי.
///
/// יורשת מ-[SearchingTab] כדי שהניווט, האייקון והכותרת יתנהגו כמו בכל חיפוש.
class SemanticSearchTab extends SearchingTab {
  SemanticSearchTab({
    required SemanticQueryOptions options,
    super.isPinned,
    this.runOnFirstShow = false,
    String? resultsId,
    this._createResultsBloc,
  }) : _options = options,
       resultsId = resultsId ?? _newResultsId(),
       super(titleFor(options.query), options.query);

  /// הוגש עכשיו מהדיאלוג. כרטיסייה משוחזרת או משוכפלת אינה מריצה חיפוש
  /// מעצמה (אין רישום בלי פעולת משתמש), אלא מציעה "חפש מחדש".
  final bool runOnFirstShow;

  /// זהות יציבה של כרטיסיית התוצאות, נשמרת בשכפול (למעקב העיון).
  final String resultsId;

  static int _nextResultsId = 0;
  static String _newResultsId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_nextResultsId++}';

  SemanticQueryOptions _options;
  final SemanticResultsBloc Function(SemanticSearchTab tab)? _createResultsBloc;
  SemanticResultsBloc? _resultsBloc;
  final _createdResultsBloc = ValueNotifier<SemanticResultsBloc?>(null);
  bool _isDisposed = false;

  /// הכותרת של כרטיסייה עם השאילתה [query].
  static String titleFor(String query) =>
      '$kSemanticSearchModeName: ${SearchingTab.shortenQueryForTitle(query.trim())}';

  /// השאילתה והאפשרויות של החיפוש האחרון שהוגש.
  SemanticQueryOptions get options => _options;

  /// נוצר בהצגה הראשונה, לא בשחזור הכרטיסיות בעלייה.
  SemanticResultsBloc get resultsBloc {
    if (_resultsBloc case final bloc?) return bloc;
    final bloc = _resultsBloc = (_createResultsBloc ?? _defaultResultsBloc)(
      this,
    );
    // נוצר בבניית המסך, ואסור לסמן את הרצועה לבנייה באותה מסגרת.
    scheduleMicrotask(() {
      if (!_isDisposed) _createdResultsBloc.value = bloc;
    });
    return bloc;
  }

  /// בלי ליצור אותו: לאבחון, שאסור לו להתחיל חיפוש.
  SemanticResultsBloc? get createdResultsBloc => _resultsBloc;

  /// מודיע כשה-BLoC נוצר, למי שמציג את מצבו בלי ליצור אותו (הרצועה).
  ValueListenable<SemanticResultsBloc?> get createdResultsBlocListenable =>
      _createdResultsBloc;

  /// מריץ חיפוש חדש בכרטיסייה ומעדכן את הכותרת.
  void submit(SemanticQueryOptions options) {
    _options = options;
    queryController.text = options.query;
    title = titleFor(options.query);
    titleNotifier.value = title;
    resultsBloc.add(SemanticSearchSubmitted(options));
  }

  /// מצמצם את התוצאות ל-[facets] בתוך ההיקף, בלי לשנות את ההיקף השמור.
  void narrow(List<String> facets) => resultsBloc.add(
    SemanticSearchSubmitted(_options.copyWith(facets: facets)),
  );

  static SemanticResultsBloc _defaultResultsBloc(SemanticSearchTab tab) =>
      SemanticResultsBloc(
        isUserBook: (item) async {
          final resolution = await tab.searchBloc.resolveBookForIndexedPath(
            item.filePath,
            indexedTitle: item.title,
          );
          return semanticResultIsPrivate(resolution.book);
        },
      );

  @override
  SemanticSearchTab clone() => SemanticSearchTab(
    options: _options,
    isPinned: isPinned,
    resultsId: resultsId,
    createResultsBloc: _createResultsBloc,
  );

  @override
  void dispose() {
    _isDisposed = true;
    _resultsBloc?.close();
    _createdResultsBloc.dispose();
    super.dispose();
  }

  factory SemanticSearchTab.fromJson(Map<String, dynamic> json) =>
      SemanticSearchTab(
        options: SemanticQueryOptions.fromJson(json),
        isPinned: json['isPinned'] == true,
      );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'SemanticSearchTab',
    'title': title,
    'isPinned': isPinned,
    ..._options.toJson(),
  };
}

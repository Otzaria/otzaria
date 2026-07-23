import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  group('formatGeneralSearchSettings — חיווי הגדרות כלליות בפריט היסטוריה', () {
    test('חיפוש ברירת מחדל (מתקדם) לא מוסיף חיווי', () {
      expect(formatGeneralSearchSettings(const SearchConfiguration()), '');
    });

    test('מצב מדויק ומקורב מוצגים', () {
      expect(
        formatGeneralSearchSettings(
          const SearchConfiguration(searchMode: SearchMode.exact),
        ),
        'מדויק',
      );
      expect(
        formatGeneralSearchSettings(
          const SearchConfiguration(searchMode: SearchMode.fuzzy),
        ),
        'מקורב',
      );
    });

    test('מרחק חיובי מוצג רק במצב מרווח מילים', () {
      expect(
        formatGeneralSearchSettings(const SearchConfiguration(distance: 3)),
        'מרחק 3',
      );
    });

    test('טווח קרבה מחליף את המרחק', () {
      expect(
        formatGeneralSearchSettings(
          const SearchConfiguration(
            distance: 3,
            proximityScope: SearchScope.sameParagraph,
          ),
        ),
        'באותה פסקה',
      );
    });

    test('התאמת מילים "לפחות X" כוללת את המספר', () {
      expect(
        formatGeneralSearchSettings(
          const SearchConfiguration(
            wordMatchMode: WordMatchMode.atLeast,
            wordMatchCount: 2,
          ),
        ),
        'לפחות 2 מילים',
      );
    });

    test('רגקס ואיחוד תוצאות מוצגים', () {
      expect(
        formatGeneralSearchSettings(
          const SearchConfiguration(
            regexEnabled: true,
            resultGrouping: ResultGroupingMode.sameSection,
          ),
        ),
        'לפי טווח (סעיף) · ביטוי רגולרי',
      );
    });

    test('כמה הגדרות מצטרפות במפריד', () {
      final label = formatGeneralSearchSettings(
        const SearchConfiguration(
          searchMode: SearchMode.fuzzy,
          distance: 2,
          wordMatchMode: WordMatchMode.mostWords,
        ),
      );
      expect(label, 'מקורב · מרחק 2 · רוב המילים');
    });
  });
}

import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

/// `OpenedTab.from` הוא מסלול השכפול: שחזור טאב שנסגר, שכפול טאב והחלפת
/// שולחן עבודה. שלושת שדות ההדגשה הם קשורי-מקור — הם מגיעים מקישור עומק
/// (`?highlight=`, `?mark=`) או משורות התוצאה שהחיפוש הגלובלי מצא — ולכן
/// חייבים לעבור בשכפול. בלעדיהם הספר המשוכפל נפתח בלי ההדגשה שהמשתמש רואה.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('שכפול טאב שלא נטען משמר את שלושת שדות ההדגשה מהשדות המקוריים', () {
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 12,
      highlightText: 'ויאמר',
      permanentHighlightLine: 7,
      initialSearchResultLines: {3, 5, 8},
    );
    addTearDown(original.dispose);
    expect(original.bloc.state, isA<TextBookInitial>());

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(clone.highlightText, 'ויאמר');
    expect(clone.permanentHighlightLine, 7);
    expect(clone.initialSearchResultLines, {3, 5, 8});
  });

  test('שכפול טאב טעון קורא את שדות ההדגשה מה-state, לא מהשדות המקוריים', () {
    // ב-Loaded השדה נקרא searchResultLines ולא initialSearchResultLines —
    // מי שיחפש את השם השני ולא ימצא, יסיק בטעות "אין מקבילה ב-state".
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 12,
      highlightText: 'ישן',
      permanentHighlightLine: 7,
      initialSearchResultLines: {3, 5, 8},
      blocOverride: StubTextBookBloc(
        _loadedState(
          highlightText: 'מעודכן',
          permanentHighlightLine: 21,
          searchResultLines: {11, 13},
        ),
      ),
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(clone.highlightText, 'מעודכן');
    expect(clone.permanentHighlightLine, 21);
    expect(clone.initialSearchResultLines, {11, 13});
  });

  test('ה-Set של שורות התוצאה מועתק ואינו משותף בין המקור לשכפול', () {
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
      initialSearchResultLines: {1, 2},
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(
      identical(
        clone.initialSearchResultLines,
        original.initialSearchResultLines,
      ),
      isFalse,
    );

    clone.initialSearchResultLines!.add(99);
    expect(original.initialSearchResultLines, {1, 2});
  });

  test('בלי שורות תוצאה השכפול מקבל null ולא Set ריק', () {
    // ההבחנה משמעותית: null = "לא רץ חיפוש מנוע", Set ריק = "רץ ולא מצא".
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(original.initialSearchResultLines, isNull);
    expect(clone.initialSearchResultLines, isNull);
  });
}

TextBookLoaded _loadedState({
  required String highlightText,
  required int? permanentHighlightLine,
  required Set<int>? searchResultLines,
}) => TextBookLoaded(
  book: TextBook(title: 'בראשית'),
  showLeftPane: false,
  content: const ['א', 'ב', 'ג'],
  fontSize: 18,
  showSplitView: true,
  showPageShapeView: false,
  activeCommentators: const <String>[],
  commentatorGroups: const [],
  availableCommentators: const <String>[],
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [12],
  selectedIndex: 12,
  pinLeftPane: false,
  searchText: '',
  highlightText: highlightText,
  permanentHighlightLine: permanentHighlightLine,
  searchResultLines: searchResultLines,
);

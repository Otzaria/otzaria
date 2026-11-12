import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

/// חמשת שדות ההדגשה לא נשמרו לדיסק, ולכן הפעלה מחדש החזירה את הספר בלי
/// ההדגשה שהמשתמש רואה ובלי סימון שורות התוצאה. ההכרעה: לשמור, ולנקות את
/// הדגשת ה-deep link כשהמשתמש מקליד חיפוש ידני חדש (ראו
/// `TextBookBloc._onUpdateSearchText`).
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('round-trip מלא — חמשת השדות שורדים שמירה וטעינה', () {
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 12,
      highlightText: 'ויאמר',
      permanentHighlightLine: 7,
      initialSearchResultLines: {3, 5, 8},
      pinpointHighlight: 'אור',
      pinpointHighlightSectionIndex: 4,
    );
    addTearDown(original.dispose);

    final restored = TextBookTab.fromJson(original.toJson());
    addTearDown(restored.dispose);

    expect(restored.highlightText, 'ויאמר');
    expect(restored.permanentHighlightLine, 7);
    expect(restored.initialSearchResultLines, {3, 5, 8});
    expect(restored.pinpointHighlight, 'אור');
    expect(restored.pinpointHighlightSectionIndex, 4);
  });

  test('תאימות לאחור — JSON בלי השדות נטען בברירות מחדל ואינו זורק', () {
    final restored = TextBookTab.fromJson({
      'title': 'בראשית',
      'initalIndex': 5,
      'commentators': <String>[],
      'showLeftPane': false,
    });
    addTearDown(restored.dispose);

    expect(restored.highlightText, isEmpty);
    expect(restored.permanentHighlightLine, isNull);
    expect(restored.initialSearchResultLines, isNull);
    expect(restored.pinpointHighlight, isNull);
    expect(restored.pinpointHighlightSectionIndex, isNull);
  });

  test('Set ריק שונה מ-null — ההבחנה שורדת את הדיסק', () {
    // null = "לא רץ חיפוש מנוע"; ריק = "רץ ולא מצא". ערבוב בין השניים
    // מדליק הדגשה על כל השורות במדיניות התאמה שאינה ברירת המחדל.
    final withEmpty = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
      initialSearchResultLines: const <int>{},
    );
    addTearDown(withEmpty.dispose);
    final restoredEmpty = TextBookTab.fromJson(withEmpty.toJson());
    addTearDown(restoredEmpty.dispose);
    expect(restoredEmpty.initialSearchResultLines, isEmpty);
    expect(restoredEmpty.initialSearchResultLines, isNotNull);

    final withNull = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
    addTearDown(withNull.dispose);
    final restoredNull = TextBookTab.fromJson(withNull.toJson());
    addTearDown(restoredNull.dispose);
    expect(restoredNull.initialSearchResultLines, isNull);
  });

  test('ערכי ברירת מחדל אינם נכתבים ל-JSON', () {
    final plain = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
    addTearDown(plain.dispose);

    final json = plain.toJson();

    expect(json.containsKey('highlightText'), isFalse);
    expect(json.containsKey('permanentHighlightLine'), isFalse);
    expect(json.containsKey('initialSearchResultLines'), isFalse);
    expect(json.containsKey('pinpointHighlight'), isFalse);
    expect(json.containsKey('pinpointHighlightSectionIndex'), isFalse);
    // המפתחות שהמסמך אוסר להוסיף.
    expect(json.containsKey('dedupeKey'), isFalse);
    expect(json.containsKey('openLeftPane'), isFalse);
  });

  test('ערך פגום נקרא כברירת מחדל ואינו זורק', () {
    final restored = TextBookTab.fromJson({
      'title': 'בראשית',
      'initalIndex': 0,
      'commentators': <String>[],
      'showLeftPane': false,
      'initialSearchResultLines': 'abc',
      'permanentHighlightLine': <String, dynamic>{},
      'pinpointHighlightSectionIndex': 'שתיים',
      'highlightText': 17,
    });
    addTearDown(restored.dispose);

    expect(restored.initialSearchResultLines, isNull);
    expect(restored.permanentHighlightLine, isNull);
    expect(restored.pinpointHighlightSectionIndex, isNull);
    expect(restored.highlightText, isEmpty);
  });

  test('state טעון גובר על השדה — הערך המעודכן הוא זה שנשמר', () {
    final tab = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 12,
      highlightText: 'ישן',
      permanentHighlightLine: 1,
      pinpointHighlight: 'ישן',
      pinpointHighlightSectionIndex: 1,
      initialSearchResultLines: {1},
      blocOverride: StubTextBookBloc(
        _loadedState(
          highlightText: 'מעודכן',
          permanentHighlightLine: 21,
          searchResultLines: {11, 13},
          pinpointHighlightText: 'ממוקד',
          pinpointHighlightIndex: 9,
        ),
      ),
    );
    addTearDown(tab.dispose);

    final json = tab.toJson();

    expect(json['highlightText'], 'מעודכן');
    expect(json['permanentHighlightLine'], 21);
    expect(json['initialSearchResultLines'], [11, 13]);
    expect(json['pinpointHighlight'], 'ממוקד');
    expect(json['pinpointHighlightSectionIndex'], 9);
  });

  test('חיפוש ידני חדש מנקה את הדגשת ה-deep link לגמרי', () {
    // בלי הניקוי ההדגשה השמורה הייתה שורדת לנצח. ושני הדגלים חייבים לנקות
    // יחד — ניקוי הטקסט לבדו היה הופך הדגשה צהובה לרקע קבוע.
    final loaded = _loadedState(
      highlightText: 'ויאמר',
      permanentHighlightLine: 7,
      searchResultLines: {3},
      pinpointHighlightText: 'אור',
      pinpointHighlightIndex: 4,
    );

    final cleared = loaded.copyWith(
      searchText: 'חדש',
      clearPinpointHighlight: true,
      clearSearchResultLines: true,
      clearHighlightText: true,
      clearPermanentHighlight: true,
    );

    expect(cleared.highlightText, isEmpty);
    expect(cleared.permanentHighlightLine, isNull);
    expect(cleared.searchResultLines, isNull);
    expect(cleared.pinpointHighlightText, isNull);
    expect(cleared.pinpointHighlightIndex, isNull);
    // לא נותרה שום הדגשה על השורה שהייתה מודגשת.
    expect(cleared.isPermanentHighlight(7), isFalse);
    expect(cleared.isHighlightYellowBackground(7), isFalse);
  });
}

TextBookLoaded _loadedState({
  required String highlightText,
  required int? permanentHighlightLine,
  required Set<int>? searchResultLines,
  String? pinpointHighlightText,
  int? pinpointHighlightIndex,
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
  pinpointHighlightText: pinpointHighlightText,
  pinpointHighlightIndex: pinpointHighlightIndex,
);

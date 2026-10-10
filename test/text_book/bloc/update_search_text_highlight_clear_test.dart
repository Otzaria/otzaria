import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

/// מאז שהדגשת ה-`?mark` נשמרת לדיסק, היא חייבת ניקוי — אחרת היא שורדת לנצח.
/// אבל הניקוי חייב להיות מותנה בשינוי אמיתי בשאילתה: חלונית החיפוש שבספר
/// מסנכרנת את ה-bloc כבר ב-`initState` שלה, עם `initialQuery: state.searchText`
/// — אותו טקסט בדיוק. ניקוי בלתי-מותנה היה מוחק הדגשת deep link ברגע שהחלונית
/// נבנית, לפני שהמשתמש הקליד תו.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextBookBloc bloc;
  late TextBook book;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 0, false, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  TextBookLoaded seed({
    required String searchText,
    SearchMode searchMode = SearchMode.exact,
  }) => TextBookLoaded(
    book: book,
    content: const ['שורה א', 'שורה ב'],
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: searchText,
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    searchMode: searchMode,
    highlightText: 'ויאמר',
    permanentHighlightLine: 1,
    // שורות שהמנוע החזיר, והדגשה ממוקדת מקישור עומק — שניהם נמחקו קודם
    // בכל `UpdateSearchText`, גם כשהבקשה לא השתנתה כלל.
    searchResultLines: const {3, 7},
    pinpointHighlightText: 'אור',
    pinpointHighlightIndex: 4,
  );

  blocTest<TextBookBloc, TextBookState>(
    'סנכרון עם אותה שאילתה — אין פליטת state כלל, וההדגשה נשמרת',
    build: () => bloc,
    seed: () => seed(searchText: 'בראשית'),
    // בדיוק מה שחלונית החיפוש שולחת ב-initState שלה.
    act: (bloc) => bloc.add(const UpdateSearchText('בראשית')),
    // ה-state שנוצר זהה לקודם, ולכן Bloc אינו פולט אותו כלל — ההוכחה
    // החזקה ביותר שסנכרון אינו משנה דבר. בלי ההגנה, ניקוי ההדגשה היה
    // יוצר state שונה ונפלט כאן.
    expect: () => const <TextBookState>[],
    verify: (bloc) {
      final state = bloc.state as TextBookLoaded;
      expect(state.highlightText, 'ויאמר');
      expect(state.permanentHighlightLine, 1);
      expect(state.isHighlightYellowBackground(1), isTrue);
      // ⚠️ הליבה של הבאג: שורות התוצאה של המנוע וההדגשה הממוקדת נמחקו
      // בכל UpdateSearchText, גם בסנכרון שלא שינה דבר. פירוש הדבר שעצם
      // פתיחת חלונית החיפוש מחקה את תוצאות החיפוש הגלובלי שהמשתמש הגיע
      // מהן — ובמדיניות התאמה שאינה ברירת המחדל, גם את ההדגשה כולה.
      expect(state.searchResultLines, {3, 7});
      expect(state.lineParticipatesInSearchHighlight(3), isTrue);
      expect(state.pinpointHighlightText, 'אור');
      expect(state.pinpointHighlightIndex, 4);
    },
  );

  blocTest<TextBookBloc, TextBookState>(
    'שינוי תצורה בלי שינוי טקסט — תוצאות המנוע כן נמחקות',
    build: () => bloc,
    seed: () => seed(searchText: 'בראשית'),
    // אותה שאילתה, מדיניות אחרת: השורות שהמנוע החזיר תקפות לצירוף
    // (שאילתה + תצורה), ולכן שינוי התצורה מבטל אותן בדיוק כמו שינוי הטקסט.
    act: (bloc) => bloc.add(
      const UpdateSearchText('בראשית', searchMode: SearchMode.fuzzy),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.searchMode, 'searchMode', SearchMode.fuzzy)
          .having((s) => s.searchResultLines, 'שורות התוצאה', isNull)
          .having((s) => s.pinpointHighlightText, 'ההדגשה הממוקדת', isNull),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'שאילתה חדשה מנקה גם את שורות התוצאה וגם את ההדגשה הממוקדת',
    build: () => bloc,
    seed: () => seed(searchText: 'בראשית'),
    act: (bloc) => bloc.add(const UpdateSearchText('שמות')),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.searchResultLines, 'שורות התוצאה', isNull)
          .having(
            (s) => s.lineParticipatesInSearchHighlight(3),
            'שער ההדגשה',
            isFalse,
          )
          .having((s) => s.pinpointHighlightText, 'ההדגשה הממוקדת', isNull)
          .having((s) => s.pinpointHighlightIndex, 'אינדקס ההדגשה', isNull),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'שאילתה חדשה — הדגשת ה-deep link נמחקת לגמרי',
    build: () => bloc,
    seed: () => seed(searchText: 'בראשית'),
    act: (bloc) => bloc.add(const UpdateSearchText('שמות')),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.highlightText, 'highlightText', isEmpty)
          .having(
            (s) => s.permanentHighlightLine,
            'permanentHighlightLine',
            isNull,
          )
          // שני הדגלים מנקים יחד: ניקוי הטקסט לבדו היה משאיר את השורה
          // מודגשת ברקע קבוע במקום להעלים את ההדגשה.
          .having((s) => s.isPermanentHighlight(1), 'הרקע הקבוע', isFalse)
          .having(
            (s) => s.isHighlightYellowBackground(1),
            'ההדגשה הצהובה',
            isFalse,
          ),
    ],
  );

  blocTest<TextBookBloc, TextBookState>(
    'ניקוי שדה החיפוש נחשב שינוי — ההדגשה נמחקת',
    build: () => bloc,
    seed: () => seed(searchText: 'בראשית'),
    act: (bloc) => bloc.add(const UpdateSearchText('')),
    expect: () => [
      isA<TextBookLoaded>()
          .having((s) => s.searchText, 'searchText', isEmpty)
          .having((s) => s.highlightText, 'highlightText', isEmpty)
          .having(
            (s) => s.permanentHighlightLine,
            'permanentHighlightLine',
            isNull,
          ),
    ],
  );
}

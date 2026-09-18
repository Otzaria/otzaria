// issue #1430: כשכבר יש טקסט בחיפוש בספר ומקלידים במקומו מילה חדשה, האות
// הראשונה מופיעה לרגע ונמחקת. השדה שולח ל-BLoC את השאילתה *המנורמלת* (אות
// בודדת בהתאמה חלקית → שאילתה ריקה), וה-state שחוזר נכנס לחלונית כ-initialQuery.
// didUpdateWidget השווה אותו לטקסט *הגולמי* בשדה, הסיק שמדובר בשינוי חיצוני
// ודרס את האות שהוקלדה.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    // בלי ספרייה מדומה, אתחול החלונית ניגש למסד הנתונים האמיתי.
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
  });

  /// בונה את חלונית החיפוש כמו מסך הספר: `initialQuery` נגזר מ-state ה-BLoC,
  /// וה-BLoC מהדהד כל UpdateSearchText חזרה אל ה-state — הזרימה האמיתית.
  Future<_EchoTextBookBloc> pumpSearchView(
    WidgetTester tester, {
    required String existingQuery,
  }) async {
    final textBookBloc = _EchoTextBookBloc(_loadedState(existingQuery));
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await textBookBloc.close();
      await settingsBloc.close();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: BlocBuilder<TextBookBloc, TextBookState>(
              builder: (context, state) => TextBookSearchView(
                contentLoader: () async => const ['שורה א'],
                scrollControler: ItemScrollController(),
                focusNode: focusNode,
                closeLeftPaneCallback: () {},
                initialQuery: (state as TextBookLoaded).searchText,
                simpleSearchRunner: (content, query) async => const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return textBookBloc;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  group('הקלדה במקום חיפוש קיים בספר (issue #1430)', () {
    testWidgets('האות הראשונה של המילה החדשה נשארת בשדה אחרי הד ה-BLoC', (
      tester,
    ) async {
      final bloc = await pumpSearchView(tester, existingQuery: 'אבג');
      expect(fieldText(tester), 'אבג');

      // המשתמש מחליף את הטקסט באות הראשונה של מילה חדשה.
      await tester.enterText(find.byType(TextField), 'ד');
      expect(fieldText(tester), 'ד');

      // הדיבאונס של השדה מעביר את ההקלדה ל-BLoC; ה-state המהדהד חוזר לחלונית.
      await tester.pump(kSearchFieldDebounce);
      await tester.pump();

      expect(
        bloc.state,
        isA<TextBookLoaded>().having(
          (s) => s.searchText,
          'searchText',
          '',
          // אות בודדת בהתאמה חלקית אינה שאילתה — ה-BLoC מקבל ריק. זה ההד
          // שנחשב בטעות לשינוי חיצוני.
        ),
      );
      expect(
        fieldText(tester),
        'ד',
        reason: 'ההד של ההקלדה אסור לו לדרוס את מה שהמשתמש הקליד',
      );
    });

    testWidgets('שינוי חיצוני אמיתי של השאילתה עדיין מסונכרן לשדה', (
      tester,
    ) async {
      final bloc = await pumpSearchView(tester, existingQuery: 'אבג');
      await tester.enterText(find.byType(TextField), 'ד');
      await tester.pump(kSearchFieldDebounce);
      await tester.pump();

      // למשל סרגל החיפוש העליון או חיפוש מתקדם קובעים שאילתה חדשה מבחוץ.
      bloc.add(const UpdateSearchText('שלום'));
      await tester.pump();

      expect(fieldText(tester), 'שלום');
    });
  });
}

TextBookLoaded _loadedState(String searchText) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
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
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

/// BLoC שמהדהד את טקסט החיפוש חזרה ל-state, כמו TextBookBloc האמיתי.
class _EchoTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _EchoTextBookBloc(super.initialState) {
    on<UpdateSearchText>((event, emit) {
      final current = state as TextBookLoaded;
      emit(current.copyWith(searchText: event.text));
    });
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

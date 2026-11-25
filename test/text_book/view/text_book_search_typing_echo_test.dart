// issue #1430: כשכבר יש טקסט בחיפוש בספר ומקלידים במקומו מילה חדשה, האות
// הראשונה מופיעה לרגע ונמחקת. השדה שולח ל-BLoC את השאילתה *המנורמלת* (אות
// בודדת בהתאמה חלקית → שאילתה ריקה), וה-state שחוזר נכנס לחלונית כ-initialQuery.
// didUpdateWidget השווה אותו לטקסט *הגולמי* בשדה, הסיק שמדובר בשינוי חיצוני
// ודרס את האות שהוקלדה.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

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
    Duration echoDelay = Duration.zero,
  }) async {
    final textBookBloc = _EchoTextBookBloc(
      _loadedState(existingQuery),
      echoDelay: echoDelay,
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      // הדים מושהים שעוד בדרך חייבים להסתיים לפני סגירת ה-BLoC.
      await tester.pump(echoDelay);
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
                lines: LineScrollController(),
                focusNode: focusNode,
                closeLeftPaneCallback: () {},
                initialQuery: (state as TextBookLoaded).searchText,
                initialQuerySource: state.searchTextSource,
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
      await tester.enterText(find.byType(TextField), 'דָּ');
      expect(fieldText(tester), 'דָּ');

      // הדיבאונס של השדה מעביר את ההקלדה ל-BLoC; ה-state המהדהד חוזר לחלונית.
      await tester.pump(kSearchFieldDebounce);
      await tester.pump();

      expect(
        bloc.state,
        isA<TextBookLoaded>().having(
          (s) => s.searchText,
          'searchText',
          'ד',
          // ה-BLoC מקבל את השאילתה בלי ניקוד — ההד שנחשב בטעות לשינוי חיצוני.
        ),
      );
      expect(
        fieldText(tester),
        'דָּ',
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
  // issue #5711: הקשה שנוחתת אחרי שהדיבאונס שלח את השאילתה ולפני שההד חזר
  // לחלונית — ההד הישן נחשב לשינוי חיצוני ודרס את האות החדשה.
  group('הקלדה מהירה בחיפוש בספר אינה מאבדת אותיות (issue #5711)', () {
    const echoDelay = Duration(milliseconds: 30);

    testWidgets('אות שהוקלדה לפני שהד ה-BLoC חזר נשארת בשדה', (tester) async {
      final bloc = await pumpSearchView(
        tester,
        existingQuery: '',
        echoDelay: echoDelay,
      );

      await tester.enterText(find.byType(TextField), 'אב');
      await tester.pump(kSearchFieldDebounce);
      await tester.enterText(find.byType(TextField), 'אבג');
      await tester.pump(echoDelay);
      await tester.pump();

      expect(fieldText(tester), 'אבג');

      await tester.pump(kSearchFieldDebounce);
      await tester.pump(echoDelay);
      await tester.pump();
      expect(fieldText(tester), 'אבג');
      expect((bloc.state as TextBookLoaded).searchText, 'אבג');
    });

    testWidgets('הקשות רצופות שכל אחת מקדימה את ההד הקודם נשמרות כולן', (
      tester,
    ) async {
      final bloc = await pumpSearchView(
        tester,
        existingQuery: '',
        echoDelay: echoDelay,
      );

      // כל הקשה נוחתת אחרי שהדיבאונס שלח את הקודמת ולפני שההד שלה חזר.
      for (final typed in ['אב', 'אבג', 'אבגד', 'אבגד ה', 'אבגד הו']) {
        await tester.enterText(find.byType(TextField), typed);
        await tester.pump(kSearchFieldDebounce);
        expect(fieldText(tester), typed);
      }
      await tester.pump(echoDelay);
      await tester.pump();

      expect(fieldText(tester), 'אבגד הו');
      expect((bloc.state as TextBookLoaded).searchText, 'אבגד הו');
    });

    testWidgets('שינוי חיצוני אחרי הקלדה עדיין מסונכרן לשדה', (tester) async {
      final bloc = await pumpSearchView(
        tester,
        existingQuery: '',
        echoDelay: echoDelay,
      );
      await tester.enterText(find.byType(TextField), 'אב');
      await tester.pump(kSearchFieldDebounce);
      await tester.pump(echoDelay);
      await tester.pump();

      bloc.add(const UpdateSearchText('שלום'));
      await tester.pump(echoDelay);
      await tester.pump();
      expect(fieldText(tester), 'שלום');

      // הסנכרון שולח את השאילתה שוב; ממתינים להד שלה.
      await tester.pump(echoDelay);
    });

    testWidgets('חיפוש חיצוני יכול לבחור מחדש את השאילתה הקיימת', (
      tester,
    ) async {
      final bloc = await pumpSearchView(tester, existingQuery: 'אב');
      await tester.enterText(find.byType(TextField), 'אבג');
      bloc.add(const UpdateSearchText('אב'));
      await tester.pump();
      expect(fieldText(tester), 'אב');
    });

    testWidgets(
      'שינוי חיצוני אחרי כמה הדים שאוגדו לפריים אחד עם שאילתה חוזרת מגיע לשדה',
      (tester) async {
        // ההדים חוזרים רק אחרי שלוש השליחות, ולכן נבנים בפריים אחד.
        const slowEcho = Duration(milliseconds: 600);
        final bloc = await pumpSearchView(
          tester,
          existingQuery: '',
          echoDelay: slowEcho,
        );
        for (final typed in ['אב', 'אבג', 'אב']) {
          await tester.enterText(find.byType(TextField), typed);
          await tester.pump(kSearchFieldDebounce);
        }
        await tester.pump(slowEcho);
        await tester.pump();
        expect(fieldText(tester), 'אב');
        expect((bloc.state as TextBookLoaded).searchText, 'אב');

        bloc.add(const UpdateSearchText('אבג'));
        await tester.pump(slowEcho);
        await tester.pump();
        expect(fieldText(tester), 'אבג');

        await tester.pump(slowEcho);
      },
    );
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
    searchText: searchText,
  );
}

/// BLoC שמהדהד את טקסט החיפוש חזרה ל-state, כמו TextBookBloc האמיתי.
class _EchoTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _EchoTextBookBloc(super.initialState, {Duration echoDelay = Duration.zero}) {
    on<UpdateSearchText>((event, emit) async {
      // ההד של ה-BLoC האמיתי מגיע לחלונית רק בפריים הבא; השהיה מדמה הקשה
      // שנוחתת בינתיים.
      if (echoDelay > Duration.zero) await Future<void>.delayed(echoDelay);
      final current = state as TextBookLoaded;
      emit(
        current.copyWith(
          searchText: event.text,
          searchTextSource: event.textSource,
        ),
      );
    });
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

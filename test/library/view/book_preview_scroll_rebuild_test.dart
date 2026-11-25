import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';

class _Recorder<E, S> extends Bloc<E, S> {
  final events = <E>[];
  _Recorder(super.initialState) {
    on<E>((event, _) => events.add(event));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabsBloc extends _Recorder<TabsEvent, TabsState> implements TabsBloc {
  _TabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));
}

class _NavigationBloc extends _Recorder<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _NavigationBloc() : super(NavigationState.initial(false));
}

class _HistoryBloc extends _Recorder<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _HistoryBloc() : super(HistoryInitial());
}

class _SettingsBloc extends _Recorder<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial());
}

class _NotesBloc extends _Recorder<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _NotesBloc() : super(const PersonalNotesState.initial());
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<TextBookBloc> pumpLoadedPreview(
    WidgetTester tester,
    TextBook book, {
    List<String>? content,
    String query = '',
    bool continuesToNextLine = false,
    ValueNotifier<int>? resultIndex,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>(create: (_) => _SettingsBloc()),
          BlocProvider<PersonalNotesBloc>(create: (_) => _NotesBloc()),
          BlocProvider<TabsBloc>(create: (_) => _TabsBloc()),
          BlocProvider<NavigationBloc>(create: (_) => _NavigationBloc()),
          BlocProvider<HistoryBloc>(create: (_) => _HistoryBloc()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: resultIndex == null
                ? BookPreviewPanel(book: book)
                : ValueListenableBuilder<int>(
                    valueListenable: resultIndex,
                    builder: (_, index, _) => BookPreviewPanel(
                      book: book,
                      initialTextIndex: index,
                      initialTextContinuesToNextLine:
                          continuesToNextLine && index == 1,
                      searchText: query,
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
    final previewBloc = BlocProvider.of<TextBookBloc>(
      tester.element(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w is BlocProvider<TextBookBloc>,
              ),
              matching: find.byWidgetPredicate((_) => true),
            )
            .last,
      ),
    );
    // הטעינה האמיתית נכשלת בלי ספרייה; ממתינים לה לפני הזרקת מצב טעון.
    for (var i = 0; i < 100; i++) {
      final state = previewBloc.state;
      if (state is! TextBookInitial && state is! TextBookLoading) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    // ignore: invalid_use_of_visible_for_testing_member
    previewBloc.emit(
      TextBookLoaded(
        book: book,
        showLeftPane: false,
        content: content ?? List.generate(200, (i) => 'שורה $i'),
        fontSize: 18,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        visibleLinks: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [0],
        selectedIndex: null,
        searchText: '',
      ),
    );
    await tester.pump();
    await tester.pump();
    return previewBloc;
  }

  Future<void> emitAndPump(
    WidgetTester tester,
    TextBookBloc bloc,
    TextBookLoaded Function(TextBookLoaded) update,
  ) async {
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(update(bloc.state as TextBookLoaded));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('מעבר לתוצאה באותו ספר מציג את ההתאמה בתוך פסקה ארוכה', (
    tester,
  ) async {
    const query = 'unique needle';
    final resultIndex = ValueNotifier(0);
    addTearDown(resultIndex.dispose);
    final bloc = await pumpLoadedPreview(
      tester,
      TextBook(title: 'ספר בדיקה'),
      resultIndex: resultIndex,
      query: query,
      content: [
        query,
        '${List.filled(500, 'word').join(' ')} $query',
        ...List.filled(15, 'end'),
      ],
    );
    await emitAndPump(
      tester,
      bloc,
      (state) => state.copyWith(searchText: query),
    );
    await tester.pumpAndSettle();
    resultIndex.value = 1;
    await tester.pumpAndSettle();
    final reader = find.byType(CombinedView);
    final text = find.descendant(
      of: reader,
      matching: find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().contains('word') &&
            w.text.toPlainText().contains(query),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(text.first);
    final offset = paragraph.text.toPlainText().indexOf(query);
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: offset,
            extentOffset: offset + query.length,
          ),
        )
        .first
        .toRect();
    final globalBox = box.shift(paragraph.localToGlobal(Offset.zero));
    expect(
      globalBox.overlaps(tester.getRect(reader)),
      isTrue,
      reason: 'Match $globalBox, preview ${tester.getRect(reader)}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }, skip: !engineReady);

  testWidgets('תוצאה שנמשכת לשורה הבאה מוצגת מסוף שורת המקור', (
    tester,
  ) async {
    const query = 'unique first second';
    final resultIndex = ValueNotifier(0);
    addTearDown(resultIndex.dispose);
    final bloc = await pumpLoadedPreview(
      tester,
      TextBook(title: 'ספר בדיקה'),
      resultIndex: resultIndex,
      query: query,
      continuesToNextLine: true,
      content: [
        query,
        '${List.filled(500, 'word').join(' ')} unique first',
        'second fragment',
        ...List.filled(15, 'end'),
      ],
    );
    await emitAndPump(
      tester,
      bloc,
      (state) => state.copyWith(searchText: query),
    );
    await tester.pumpAndSettle();
    resultIndex.value = 1;
    await tester.pumpAndSettle();

    final reader = find.byType(CombinedView);
    final nextLine = find.descendant(
      of: reader,
      matching: find.byWidgetPredicate(
        (w) =>
            w is RichText && w.text.toPlainText().contains('second fragment'),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(nextLine.first);
    final globalBox = paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: paragraph.text.toPlainText().length,
          ),
        )
        .first
        .toRect()
        .shift(paragraph.localToGlobal(Offset.zero));
    expect(
      globalBox.overlaps(tester.getRect(reader)),
      isTrue,
      reason: 'Next result line $globalBox, preview ${tester.getRect(reader)}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }, skip: !engineReady);

  testWidgets('גלילה בתצוגה המקדימה אינה בונה מחדש את הקורא', (tester) async {
    final bloc = await pumpLoadedPreview(tester, TextBook(title: 'ספר בדיקה'));
    final before = tester.widget(find.byType(CombinedView));

    for (var i = 1; i <= 5; i++) {
      await emitAndPump(
        tester,
        bloc,
        (s) => s.copyWith(visibleIndices: [i, i + 1]),
      );
      expect(tester.widget(find.byType(CombinedView)), same(before));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('שינוי תוכן בתצוגה המקדימה עדיין מגיע לקורא', (tester) async {
    final bloc = await pumpLoadedPreview(tester, TextBook(title: 'ספר בדיקה'));
    final before = tester.widget<CombinedView>(find.byType(CombinedView));

    await emitAndPump(tester, bloc, (s) => s.copyWith(content: ['אחרת']));

    final after = tester.widget<CombinedView>(find.byType(CombinedView));
    expect(after, isNot(same(before)));
    expect(after.data, ['אחרת']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// מקש התפריט (Menu / Shift+F10) בקורא: הפוקוס על ה-Focus של המסך כולו, ולכן
/// נפתחת שורה אחת מבין הנראות. ההכרעה (סעיף 10): השורה הנבחרת, ורק כשאין
/// כזו השורה העליונה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  const lines = [
    'שורה א',
    'שורה ב',
    'שורה ג',
    'שורה ד',
    'שורה ה',
    'שורה ו',
    'שורה ז',
    'שורה ח',
  ];

  Future<void> pumpViewer(
    WidgetTester tester, {
    Set<int> selected = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bloc = _Bloc(_state(selected));
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settings = StubSettingsBloc(SettingsState.initial());
    addTearDown(() async {
      await bloc.close();
      await notes.close();
      await settings.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: Scaffold(
            body: SimpleTextViewer(
              content: lines,
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// פותח את התפריט במקש ומחזיר את המיקום האנכי של הפריט הראשון בו.
  Future<double> openByKeyboard(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    final first = find.text('חיפוש').first;
    expect(
      find.text('דווח על טעות בספר'),
      findsOneWidget,
      reason: 'התפריט נפתח',
    );
    return tester.getTopLeft(first).dy;
  }

  Rect line(WidgetTester tester, int index) =>
      tester.getRect(find.byType(AppContextMenuRegion).at(index));

  testWidgets('בלי שורה נבחרת נפתח תפריט השורה העליונה', (tester) async {
    await pumpViewer(tester);

    final menuTop = await openByKeyboard(tester);

    expect(
      menuTop,
      lessThan(line(tester, 3).top),
      reason: 'התפריט נפתח בגובה השורה העליונה',
    );
  });

  testWidgets('עם שורה נבחרת נפתח תפריט השורה הנבחרת', (tester) async {
    await pumpViewer(tester, selected: {6});

    final menuTop = await openByKeyboard(tester);

    expect(
      menuTop,
      greaterThan(line(tester, 3).bottom),
      reason: 'התפריט לא נפתח בגובה השורות העליונות',
    );
  });
}

TextBookLoaded _state(Set<int> selected) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const [
    'שורה א',
    'שורה ב',
    'שורה ג',
    'שורה ד',
    'שורה ה',
    'שורה ו',
    'שורה ז',
    'שורה ח',
  ],
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0, 1, 2, 3, 4, 5, 6, 7],
  selectedIndex: selected.isEmpty ? 0 : selected.first,
  selectedIndices: selected,
  pinLeftPane: false,
  searchText: '',
);

class _Bloc extends Bloc<TextBookEvent, TextBookState> implements TextBookBloc {
  _Bloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _Repository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/links_notes_sidebar.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    if (!Settings.isInitialized) {
      await Settings.init();
    }
  });

  testWidgets('פותח טאב הערות לפי initialTabIndex ומדווח על שינוי טאבים',
      (tester) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final personalNotesBloc =
        _TestPersonalNotesBloc(const PersonalNotesState.initial());
    var selectedTab = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          ],
          child: LinksNotesSidebar(
            bookId: 'ספר בדיקה',
            openBookCallback: (_) {},
            fontSize: 18,
            initialTabIndex: 1,
            onNavigateToLine: (_) {},
            onClosePane: () {},
            onTabChanged: (index) => selectedTab = index,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('הערות'), findsOneWidget);
    expect(find.text('קישורים'), findsOneWidget);
    expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsNothing);

    await tester.tap(find.text('קישורים'));
    await tester.pumpAndSettle();

    expect(selectedTab, 0);
    expect(find.text('לא נמצאו קישורים לקטע הנבחר'), findsOneWidget);
  });

  testWidgets('כפתור הסגירה מזמן את callback הסגירה', (tester) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final personalNotesBloc =
        _TestPersonalNotesBloc(const PersonalNotesState.initial());
    var wasClosed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          ],
          child: LinksNotesSidebar(
            bookId: 'ספר בדיקה',
            openBookCallback: (_) {},
            fontSize: 18,
            onNavigateToLine: (_) {},
            onClosePane: () => wasClosed = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
    await tester.pumpAndSettle();

    expect(wasClosed, isTrue);
  });
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
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
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

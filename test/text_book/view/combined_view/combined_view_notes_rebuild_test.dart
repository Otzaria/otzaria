import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';

const _lines = ['פסקה ראשונה', 'פסקה שניה', 'פסקה שלישית'];
const _bookTitle = 'ספר בדיקה';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  SmoothWheelScroll list(WidgetTester tester) =>
      tester.widget<SmoothWheelScroll>(find.byType(SmoothWheelScroll).first);

  testWidgets('הקלדה בחיפוש ההערות אינה בונה מחדש את רשימת הטקסט', (
    tester,
  ) async {
    final notes = [_note()];
    final notesBloc = await _pumpView(tester, _notesState(notes));
    final before = list(tester);

    notesBloc.emit(_notesState(notes).copyWith(searchQuery: 'תו'));
    await tester.pumpAndSettle();

    // בנייה מחדש עלתה כ-20ms לכל הקשה בבראשית.
    expect(identical(list(tester), before), isTrue);
  });

  testWidgets('הוספת הערה בונה מחדש את הרשימה ומסמנת את השורה', (
    tester,
  ) async {
    final notesBloc = await _pumpView(tester, _notesState(const []));
    final before = list(tester);

    notesBloc.emit(_notesState([_note(line: 2)]));
    await tester.pumpAndSettle();

    expect(identical(list(tester), before), isFalse);
  });

  // #2519: אין חסימה. הריחוף מציג את ההערה תמיד, גם כשלשונית ההערות פתוחה
  // בחלונית הצד (התצוגה כבר לא יודעת אם היא פתוחה).
  testWidgets('ריחוף על סימון הערה מציג את ההערה בחלונית צפה', (tester) async {
    addTearDown(LinkPreviewOverlay.dismiss);
    await _pumpView(tester, _notesState([_note()]));
    await tester.pumpAndSettle();

    tester
        .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
        .firstWhere((w) => w.onAnchorHover != null)
        .onAnchorHover!('otzaria://note?line=0', const Offset(400, 100));
    await tester.pump(AppTokens.hoverPreviewDelay);
    await tester.pump();

    expect(find.text('תוכן'), findsOneWidget);
  });
}

PersonalNote _note({int line = 1}) {
  final now = DateTime(2026, 10, 4);
  return PersonalNote(
    id: '$line',
    bookId: _bookTitle,
    lineNumber: line,
    displayTitle: 'שורה',
    lastKnownLineNumber: line,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

PersonalNotesState _notesState(List<PersonalNote> notes) => PersonalNotesState(
  isLoading: false,
  bookId: _bookTitle,
  locatedNotes: notes,
  missingNotes: const [],
  errorMessage: null,
  filteredLocatedNotes: notes,
  filteredMissingNotes: const [],
);

Future<_PersonalNotesBloc> _pumpView(
  WidgetTester tester,
  PersonalNotesState notesState,
) async {
  final book = TextBook(title: _bookTitle);
  final bloc = _TextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: _lines,
      fontSize: 18,
      showSplitView: false,
      showPageShapeView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: headerToc(_lines),
      removeNikud: false,
      visibleIndices: List.generate(_lines.length, (index) => index),
      selectedIndex: null,
      selectedIndices: const {},
      continuousReadingMode: false,
      pinLeftPane: false,
      searchText: '',
    ),
  );
  final settingsBloc = _SettingsBloc(SettingsState.initial());
  final notesBloc = _PersonalNotesBloc(notesState);
  final tab = TextBookTab(book: book, index: 0);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    tab.dispose();
    await bloc.close();
    await settingsBloc.close();
    await notesBloc.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CombinedView(
            data: _lines,
            openBookCallback: (_) {},
            openLeftPaneTab: (_, {searchText}) {},
            textSize: 18,
            showCommentaryAsExpansionTiles: true,
            onOpenPersonalNotes: () {},
            tab: tab,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return notesBloc;
}

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _PersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

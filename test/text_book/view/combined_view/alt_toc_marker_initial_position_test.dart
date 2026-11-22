import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// #5748: כל סעיפי הסימן בשורה אחת; הטאב נפתח בסמן [סעיף ו] שבתוכה.
const _target = 5;
final _filler = List.filled(
  60,
  'דברי הברית אשר צוה לכרת את בני ישראל',
).join(' ');
final _content = [
  for (var i = 0; i < 20; i++)
    i == _target
        ? '[סעיף א] $_filler [סעיף ו] יעדמדויק $_filler'
        : 'שורה $i: דברי הברית אשר צוה',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  testWidgets('טאב חדש נפתח בסמן שבתוך השורה', (tester) async {
    await _pump(tester, markerReference: 'טור סימן שח סעיף ו');

    final list = tester.getRect(find.byType(ScrollablePositionedList));
    final anchor = list.top + kReadingAnchorAlignment * list.height;
    expect(_rowTopOf(tester, 'יעדמדויק'), closeTo(anchor, 40));
  });

  testWidgets('בלי הפניה נפתח בתחילת השורה', (tester) async {
    await _pump(tester);

    final list = tester.getRect(find.byType(ScrollablePositionedList));
    final anchor = list.top + kReadingAnchorAlignment * list.height;
    expect(_rowTopOf(tester, '[סעיף א]'), closeTo(anchor, 40));
  });
}

double _rowTopOf(WidgetTester tester, String text) {
  final paragraph = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere((p) => p.text.toPlainText().contains(text));
  final offset = paragraph.text.toPlainText().indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
        boxHeightStyle: ui.BoxHeightStyle.max,
      )
      .first;
  return paragraph.localToGlobal(Offset(0, box.top)).dy;
}

Future<void> _pump(WidgetTester tester, {String? markerReference}) async {
  final book = TextBook(title: 'טור', categoryId: 7);
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: _content,
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
      visibleIndices: const [_target],
      pinLeftPane: false,
      searchText: '',
    ),
  );
  final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  final tab = TextBookTab(
    book: book,
    index: _target,
    markerReference: markerReference,
  );
  addTearDown(bloc.close);
  addTearDown(notes.close);
  addTearDown(settings.close);
  addTearDown(tab.dispose);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: Scaffold(
          body: CombinedView(
            data: _content,
            openBookCallback: (_) {},
            openLeftPaneTab: (_, {searchText}) {},
            textSize: 18,
            showCommentaryAsExpansionTiles: false,
            tab: tab,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
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

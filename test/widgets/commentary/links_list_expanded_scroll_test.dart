// קישור פתוח שחוזר בגלילה מעבר לתחום המטמון של הרשימה נבנה מחדש. אם הוא
// מתחיל בשלד טעינה, הוא גדל אחריו ודוחף את הרשימה (כמו issue #1588 במפרשים).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_settings_bloc.dart';

/// כמו קישורי בראשית א, א: ספרים רבים, ולכל אחד הפניות רבות.
const _books = {
  'אגרא דכלה': 40,
  'ספר הזהר': 20,
  'בת עין': 15,
  'ישמח משה': 15,
  'שני לוחות הברית': 10,
  'רבנו בחיי': 10,
  'בראשית רבה': 10,
  'תנחומא בובר': 10,
  'מדרש תנחומא': 10,
  'ילקוט שמעוני על התורה': 10,
};

final _links = [
  for (final MapEntry(key: book, value: count) in _books.entries)
    for (var i = 1; i <= count; i++)
      Link(
        heRef: '$book, ${toHebrewNumeral(i)}',
        index1: 3,
        path2: book,
        index2: i,
        connectionType: i.isEven ? LinkTypes.reference : LinkTypes.other,
      ),
];

/// פירוש ארוך: קישור פתוח גבוה מחצי מסך.
class _Provider extends Fake implements LibraryProvider {
  static var repeat = 40;

  @override
  bool get isInitialized => false;

  @override
  Future<String> getLinkContent(Link link) async =>
      List.filled(repeat, 'מילה ארוכה בתוך פירוש ${link.index2}').join(' ');
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    _Provider.repeat = 40;
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {},
      providers: [_Provider()],
    );
    Link.clearContentCache();
    CommentaryService.seedEraCache({
      for (final book in _books.keys) book: CommentaryEra.other,
    });
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
    Link.clearContentCache();
    CommentaryService.clearEraCache();
  });

  testWidgets('לשונית הקישורים בטקסט: קישור פתוח חוזר בגלילה בלי שלד טעינה', (
    tester,
  ) async {
    await _pumpTextLinks(tester);
    await _expectExpandedLinkReturnsLoaded(tester);
  });

  testWidgets('אחרי רענון מסד: קישור פתוח חוזר בגלילה בתוכן שהרשימה מציגה', (
    tester,
  ) async {
    await _pumpTextLinks(tester);
    await _expectExpandedLinkReturnsLoaded(
      tester,
      // רענון מסד מנקה את מטמון התוכן של Link, ומשטח אחר טוען את התוכן החדש.
      afterExpand: () async {
        Link.clearContentCache();
        _Provider.repeat = 2;
        await Future.wait(_links.map((link) => link.content));
      },
    );
  });

  testWidgets('לשונית הקישורים ב-PDF: קישור פתוח חוזר בגלילה בלי שלד טעינה', (
    tester,
  ) async {
    final tab = PdfBookTab(
      book: PdfBook(title: 'בראשית', path: '/books/בראשית.pdf'),
      pageNumber: 1,
    );
    tab.currentTextLineNumber = 1;
    tab.currentTextLineNumberEnd = 10;
    tab.links = _links;
    final settings = StubSettingsBloc();
    final notes = _PersonalNotesBloc();
    addTearDown(tab.dispose);
    addTearDown(settings.close);
    addTearDown(notes.close);
    await _pump(
      tester,
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
        ],
        child: PdfCommentaryPanel(
          tab: tab,
          linksCount: tab.links.length,
          linksLoading: false,
          openBookCallback: (_) {},
          fontSize: 16,
          initialTabIndex: 1,
        ),
      ),
    );
    await _expectExpandedLinkReturnsLoaded(tester);
  });
}

Future<void> _pumpTextLinks(WidgetTester tester) async {
  final bloc = _TextBookBloc(_textState());
  final settings = StubSettingsBloc();
  addTearDown(bloc.close);
  addTearDown(settings.close);
  await _pump(
    tester,
    MultiBlocProvider(
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<SettingsBloc>.value(value: settings),
      ],
      child: SelectedLineLinksView(openBookCallback: (_) {}, fontSize: 18),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget panel) async {
  tester.view.physicalSize = const Size(500, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: panel),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// פותח קישור, גולל עד שהוא יוצא מתחום המטמון של הרשימה, וחוזר אליו: בגלגלת
/// רגילה (600 פיקסלים לפריים) ובגלגלת מהירה (שישה צעדים באותו פריים).
Future<void> _expectExpandedLinkReturnsLoaded(
  WidgetTester tester, {
  Future<void> Function()? afterExpand,
}) async {
  final list = find.descendant(
    of: find.byType(LinksListView),
    matching: find.byType(ScrollablePositionedList),
  );
  final wheelAt = tester.getCenter(list);
  final tile = find
      .descendant(of: list, matching: find.byType(ExpansionTile))
      .at(1);
  final key = tester.widget<ExpansionTile>(tile).key!;
  await tester.tap(
    find.descendant(of: tile, matching: find.byType(ListTile)).first,
  );
  await tester.pumpAndSettle();
  await afterExpand?.call();
  await tester.pumpAndSettle();
  final expanded = find.byKey(key, skipOffstage: false);
  final height = tester.getSize(expanded).height;
  expect(height, greaterThan(350), reason: 'הבדיקה צריכה קישור פתוח גבוה');

  ScrollPosition position() => tester
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      )
      .position;
  // גם מחוץ לתצוגה: שם, בתחום המטמון, הפריט נבנה וגדל לפני שהוא נראה.
  final loading = find.descendant(
    of: list,
    matching: find.byType(LoadingIndicator, skipOffstage: false),
    skipOffstage: false,
  );

  for (final notches in [1, 6]) {
    Future<void> wheel(double dy) async {
      for (var i = 0; i < notches; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: wheelAt, scrollDelta: Offset(0, dy)),
        );
      }
      await tester.pump();
    }

    var frames = 0;
    while (expanded.evaluate().isNotEmpty && frames < 30) {
      await wheel(600);
      frames++;
    }
    expect(expanded, findsNothing, reason: 'הקישור חייב לצאת מתחום המטמון');
    await tester.pumpAndSettle();

    for (var step = 0; step < frames + 2; step++) {
      final at = 'גלגלת x$notches, פריים $step';
      final before = _visibleTileTops(list);
      final pixels = position().pixels;
      await wheel(-600);
      expect(
        loading,
        findsNothing,
        reason: '$at: קישור שתוכנו כבר נטען נבנה בשלד טעינה',
      );
      if (expanded.evaluate().isNotEmpty) {
        expect(
          tester.getSize(expanded).height,
          moreOrLessEquals(height, epsilon: 0.5),
          reason: '$at: הקישור הפתוח נבנה בגובה אחר',
        );
      }
      final moved = pixels - position().pixels;
      final after = _visibleTileTops(list);
      for (final tileKey in before.keys.where(after.containsKey)) {
        expect(
          after[tileKey]! - before[tileKey]!,
          moreOrLessEquals(moved, epsilon: 0.5),
          reason: '$at: $tileKey זז שלא כמו מיקום הגלילה',
        );
      }
    }
    expect(find.byKey(key), findsOneWidget);
  }
}

Map<Key, double> _visibleTileTops(Finder list) => {
  for (final element
      in find
          .descendant(of: list, matching: find.byType(ExpansionTile))
          .evaluate())
    element.widget.key!: (element.renderObject! as RenderBox)
        .localToGlobal(Offset.zero)
        .dy,
};

TextBookLoaded _textState() => TextBookLoaded(
  book: TextBook(title: 'בראשית'),
  showLeftPane: true,
  content: const ['בראשית', 'פרק א', 'בראשית ברא אלהים'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: _links,
  visibleLinks: _links,
  linksByLine: {3: _links},
  selectedLinkTypes: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [2],
  selectedIndex: 2,
  selectedIndices: const {2},
  pinLeftPane: false,
  searchText: '',
);

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
  _PersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

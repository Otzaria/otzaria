import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';

import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

/// עט בוחר טקסט בגרירה כמו עכבר גם באזורי הבחירה של הקורא והמפרשים (סעיף 9).
///
/// ל-`SelectableRegion` של Flutter גרירת עט היא כמו גרירת אצבע: לא בוחרת
/// טקסט ולא מעדכנת את `onSelectionChanged`. כל אתר כאן שומר את הבחירה בעצמו
/// מ-`onSelectionChanged`, ולכן כל בדיקה בודקת שני דברים: שהטקסט אכן סומן,
/// ושהאתר קיבל את הבחירה ושמר אותה. בקרה בעכבר נבדקת באותה סצנה, כדי שכשל של
/// העט לא יוסתר על ידי סצנה שבורה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): FakeCommentaryLibraryProvider(),
      },
      providers: [FakeCommentaryLibraryProvider()],
    );
    BookProtectionRepository.instance.debugRepositoryFor = (_) async => null;
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
    BookProtectionRepository.instance.debugReset();
  });

  _penSite('simple_text_viewer (צורת הדף)', (tester) async {
    const line = 'שורה ארוכה של טקסט שנבחר בגרירה של עט';
    final bloc = _RecordingTextBookBloc(_loadedState(const [line]));
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settings = StubSettingsBloc();
    addTearDown(() async {
      await bloc.close();
      await notes.close();
      await settings.close();
    });
    await _pumpApp(
      tester,
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<PersonalNotesBloc>.value(value: notes),
        BlocProvider<SettingsBloc>.value(value: settings),
      ],
      child: SimpleTextViewer(
        content: const [line],
        fontSize: 18,
        openBookCallback: (_) {},
        isMainText: true,
      ),
    );
    return _Probe(
      text: find.textContaining('שורה ארוכה', findRichText: true),
      saved: () => bloc.received.whereType<UpdateSelectedTextForNote>().any(
        (e) => e.text != null && e.text!.isNotEmpty,
      ),
    );
  });

  _penSite('combined_book_screen (תצוגה משולבת)', (tester) async {
    const line = 'שורה ארוכה של טקסט שנבחר בגרירה של עט';
    final bloc = _RecordingTextBookBloc(_loadedState(const [line]));
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settings = StubSettingsBloc();
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      tab.dispose();
      await bloc.close();
      await notes.close();
      await settings.close();
    });
    final reported = <String?>[];
    await _pumpApp(
      tester,
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<PersonalNotesBloc>.value(value: notes),
        BlocProvider<SettingsBloc>.value(value: settings),
      ],
      child: CombinedView(
        data: const [line],
        openBookCallback: (_) {},
        openLeftPaneTab: (_, {searchText}) {},
        textSize: 18,
        showCommentaryAsExpansionTiles: true,
        onSelectedTextChanged: (text, index, column) => reported.add(text),
        tab: tab,
      ),
    );
    return _Probe(
      text: find.textContaining('שורה ארוכה', findRichText: true),
      saved: () => reported.any((t) => t != null && t.isNotEmpty),
    );
  });

  _penSite('commentary_list_base (רשימת המפרשים)', (tester) async {
    final controller = SelectionSyncController();
    final bloc = StubTextBookBloc(_commentaryState());
    final settings = StubSettingsBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      controller.dispose();
      await bloc.close();
      await settings.close();
    });
    await _pumpApp(
      tester,
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<SettingsBloc>.value(value: settings),
      ],
      child: CommentaryListBase(
        openBookCallback: (_) {},
        fontSize: 18,
        showSearch: false,
        shrinkWrap: false,
        selectionSyncController: controller,
      ),
      settle: false,
    );
    const commentary = 'פירוש לבדיקה';
    await _pumpUntil(
      tester,
      () => find
          .textContaining(commentary, findRichText: true)
          .evaluate()
          .isNotEmpty,
    );
    await tester.pump();
    // גוררים מעל כותרת המפרש (הפסקה הראשונה ברשימה). גרירה בעכבר בגוף
    // הפירוש בסצנת הבדיקה מתכווצת לתחילת הרשימה (נצפה, לא נחקר), ולכן לא
    // משמשת כאן גם כבקרה.
    return _Probe(
      text: find.text('מפרש בדיקה', findRichText: true),
      saved: () => controller.activeOwner != null,
    );
  });

  _penSite('commentary_list_base (מפרש "הערות")', (tester) async {
    final controller = SelectionSyncController();
    const body = 'גוף ההערה שנבחר בגרירה של עט';
    final bloc = StubTextBookBloc(
      _loadedState(
        const [
          'גוף הפסוק<sup class="footnote-marker">א</sup>'
              '<i class="footnote">$body</i>',
        ],
        activeCommentators: const [kNotesCommentatorTitle],
      ),
    );
    final settings = StubSettingsBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      controller.dispose();
      await bloc.close();
      await settings.close();
    });
    await _pumpApp(
      tester,
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<SettingsBloc>.value(value: settings),
      ],
      child: CommentaryListBase(
        openBookCallback: (_) {},
        fontSize: 18,
        showSearch: false,
        shrinkWrap: false,
        selectionSyncController: controller,
      ),
    );
    return _Probe(
      text: find.text('הערות', findRichText: true),
      saved: () => controller.activeOwner != null,
    );
  });

  _penSite('links_list_view (רשימת הקישורים)', (tester) async {
    final controller = SelectionSyncController();
    final settings = StubSettingsBloc();
    final link = _ContentLink(
      heRef: 'ציטוט בדיקה',
      index1: 1,
      path2: 'ספר יעד',
      index2: 1,
      connectionType: 'reference',
      body: 'תוכן הקישור שנבחר בגרירה של עט',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      controller.dispose();
      await settings.close();
    });
    await _pumpApp(
      tester,
      providers: [BlocProvider<SettingsBloc>.value(value: settings)],
      child: LinksListView(
        displayProfile: TextDisplayProfile.defaults,
        links: [link],
        chipSourceLinks: [link],
        openBookTitle: 'ספר בדיקה',
        selectedLinkTypes: const {},
        onSelectedLinkTypesChanged: (_) {},
        openBookCallback: (_) {},
        fontSize: 18,
        selectionSyncController: controller,
      ),
    );
    // התוכן מוצג רק בקישור פתוח.
    await tester.tap(find.textContaining('ציטוט בדיקה'));
    await tester.pumpAndSettle();
    return _Probe(
      text: find.textContaining('תוכן הקישור', findRichText: true),
      saved: () => controller.activeOwner != null,
    );
  });

  _penSite('pdf_commentary_panel (מפרשי PDF)', (tester) async {
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settings = StubSettingsBloc();
    final tab = PdfBookTab(
      book: PdfBook(title: 'מכות', path: '/books/מכות.pdf'),
      pageNumber: 1,
    );
    tab.currentTextLineNumber = 1;
    tab.currentTextLineNumberEnd = 1;
    tab.links = [
      Link(
        heRef: 'בראשית א',
        index1: 1,
        path2: 'מפרש בדיקה.txt',
        index2: 1,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      ),
    ];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      tab.dispose();
      await notes.close();
      await settings.close();
    });
    await _pumpApp(
      tester,
      providers: [
        BlocProvider<SettingsBloc>.value(value: settings),
        BlocProvider<PersonalNotesBloc>.value(value: notes),
      ],
      child: PdfCommentaryPanel(
        tab: tab,
        linksCount: tab.links.length,
        linksLoading: false,
        openBookCallback: (_) {},
        fontSize: 18,
        initialTabIndex: 0,
        isFullScreen: true,
        enableInternalFilter: false,
      ),
      settle: false,
    );
    await _pumpUntil(
      tester,
      () => find
          .textContaining('פירוש לבדיקה', findRichText: true)
          .evaluate()
          .isNotEmpty,
    );
    await tester.pump();
    return _Probe(
      text: find.text('מפרש בדיקה', findRichText: true),
      // הפאנל לא חושף את הבחירה השמורה שלו; נבדקת רק הבחירה עצמה.
      saved: null,
    );
  });
}

/// אתר בחירה אחד: מגדיר בדיקת עט, ובקרת עכבר על אותה סצנה.
void _penSite(String name, Future<_Probe> Function(WidgetTester) pump) {
  for (final kind in [PointerDeviceKind.stylus, PointerDeviceKind.mouse]) {
    final who = kind == PointerDeviceKind.stylus ? 'עט' : 'עכבר (בקרה)';
    testWidgets('$name: גרירת $who בוחרת טקסט והאתר שומר אותו', (tester) async {
      final probe = await pump(tester);

      await _dragAcross(tester, probe.text, kind);
      expect(
        _selectionWidth(tester, probe.text),
        greaterThan(60),
        reason: '$kind: הטקסט סומן',
      );
      final saved = probe.saved;
      if (saved != null) {
        expect(saved(), isTrue, reason: '$kind: האתר קיבל ושמר את הבחירה');
      }
    });
  }
}

class _Probe {
  const _Probe({required this.text, required this.saved});

  /// הטקסט שגוררים מעליו.
  final Finder text;

  /// האם האתר שמר את הבחירה (לפי מה שהוא חושף); null כשהאתר לא חושף.
  final bool Function()? saved;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required List<BlocProvider> providers,
  required Widget child,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      theme: ThemeData(platform: TargetPlatform.windows),
      home: MultiBlocProvider(
        providers: providers,
        child: Scaffold(body: child),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// שואב פריימים עד שהתנאי מתקיים (טעינה דרך Future).
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTries = 80,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// גרירה אופקית מעל כל הטקסט, מקצהו הימני אל מעבר לקצהו השמאלי.
Future<void> _dragAcross(
  WidgetTester tester,
  Finder textFinder,
  PointerDeviceKind kind,
) async {
  final rect = tester.getRect(textFinder.first);
  final y = rect.center.dy;
  final gesture = await tester.startGesture(
    Offset(rect.right - 5, y),
    kind: kind,
  );
  await tester.pump();
  for (var x = rect.right - 5; x > rect.left; x -= 25) {
    await gesture.moveTo(Offset(x, y));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.moveTo(Offset(rect.left + 5, y));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// רוחב הבחירה של האזור שמכיל את הטקסט בפיקסלים; 0 כשאין בחירה.
double _selectionWidth(WidgetTester tester, Finder textFinder) {
  final region = tester.state<SelectableRegionState>(
    find
        .ancestor(of: textFinder.first, matching: find.byType(SelectableRegion))
        .first,
  );
  try {
    final points = region.selectionEndpoints;
    if (points.length < 2) return 0;
    return (points.first.point.dx - points.last.point.dx).abs();
  } on TypeError {
    // ב-Flutter ה-getter מפעיל null assertion כשאין קצוות בחירה.
    return 0;
  }
}

TextBookLoaded _loadedState(
  List<String> content, {
  List<String> activeCommentators = const [],
}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: content,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: activeCommentators,
  commentatorGroups: const [],
  availableCommentators: activeCommentators,
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

TextBookLoaded _commentaryState() {
  final link = Link(
    heRef: 'בראשית א',
    index1: 1,
    path2: 'מפרש בדיקה.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
  );
}

class _RecordingTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _RecordingTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }

  final List<TextBookEvent> received = [];

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

class _ContentLink extends Link {
  _ContentLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
    required this.body,
  });

  final String body;

  @override
  Future<String> get content => Future.value(body);

  @override
  Future<String> get displayReference => Future.value(fallbackDisplayReference);
}

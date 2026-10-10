import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

import '../helpers/memory_settings_cache.dart';

// כותרות ייחודיות: מטמון התוכן של Link סטטי ומשותף לכל הבדיקות.
const _commentatorPrefix = 'מפרש רשימה עצלה PDF';
const _groupCount = 60;
late _FakeLibraryProvider _provider;

// ריפוד באפסים: מיון הקישורים לפי כותרת שווה למיון המספרי.
String _title(int i) => '$_commentatorPrefix ${i.toString().padLeft(2, "0")}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    final provider = _provider = _FakeLibraryProvider();
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (var i = 1; i <= _groupCount; i++)
          BookCompositeKey.create(
            title: _title(i),
            categoryId: 1,
            fileType: 'txt',
          ): provider,
      },
      providers: [provider],
    );
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  testWidgets('בחירה מלאה מעתיקה גם קטעים שטרם נבנו', (tester) async {
    final tab = _bigGroupTab(100);
    addTearDown(tab.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_wrap(_panel(tab)));
    await tester.pumpAndSettle();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion).first,
    );
    region.selectAll();
    region.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect('טָהוֹר'.allMatches(copied!).length, 100);
    expect(
      find.byType(CommentaryContent, skipOffstage: false).evaluate().length,
      lessThan(40),
    );

    region.selectAll();
    tester
        .widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList))
        .itemScrollController!
        .jumpTo(index: 85);
    await tester.pumpAndSettle();
    copied = null;
    region.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect('טָהוֹר'.allMatches(copied!).length, 100);
  });

  testWidgets('בחירה מלאה מתחלפת בבחירה חלקית native', (tester) async {
    final tab = _bigGroupTab(100, group: 7);
    addTearDown(tab.dispose);
    final copy = _ClipboardCapture(tester);
    await tester.pumpWidget(_wrap(_panel(tab)));
    await tester.pumpAndSettle();
    copy.selectAll();
    final region = copy.region;
    String? copied;
    final paragraph = find
        .descendant(
          of: find.byType(CommentaryContent).hitTestable().first,
          matching: find.byWidgetPredicate((widget) => widget is RichText),
        )
        .evaluate()
        .map((e) => e.renderObject)
        .whereType<RenderParagraph>()
        .firstWhere((p) => p.text.toPlainText().contains('טָהוֹר'));
    region.selectAll();
    final wordBox = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: 'דְּבֵין'.length),
        )
        .first
        .toRect();
    final gesture = await tester.startGesture(
      paragraph.localToGlobal(Offset(wordBox.right + 1, wordBox.center.dy)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(
      paragraph.localToGlobal(
        Offset(wordBox.left - 1, wordBox.center.dy),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    await copy.copy();
    copied = copy.text;
    expect(copied, ' עָמֹק בֵּין דֵּהֶה טָהוֹר');
  });

  testWidgets('כיווץ מוחק בחירה ישנה ובחירה מלאה כוללת כותרת סגורה בלבד', (
    tester,
  ) async {
    final tab = _bigGroupTab(100);
    addTearDown(tab.dispose);
    final copy = _ClipboardCapture(tester);
    await tester.pumpWidget(_wrap(_panel(tab)));
    await tester.pumpAndSettle();
    copy.selectAll();
    tester
        .state<PdfCommentaryPanelState>(find.byType(PdfCommentaryPanel))
        .toggleAllExpanded();
    await tester.pumpAndSettle();
    await copy.copy();
    expect(copy.text, isNull);
    copy.selectAll();
    await copy.copy();
    expect(copy.text, _title(1));
    tester
        .state<PdfCommentaryPanelState>(find.byType(PdfCommentaryPanel))
        .toggleAllExpanded();
    await tester.pumpAndSettle();
    copy.selectAll();
    await copy.copy();
    expect('טָהוֹר'.allMatches(copy.text!).length, 100);
  });

  testWidgets('שינוי פרופיל מבטל בחירה ישנה ומעתיק את הניקוד המוצג', (
    tester,
  ) async {
    final tab = _bigGroupTab(100);
    addTearDown(tab.dispose);
    final copy = _ClipboardCapture(tester);
    await tester.pumpWidget(_wrap(_panel(tab)));
    await tester.pumpAndSettle();
    copy.selectAll();
    await tester.pumpWidget(
      _wrap(
        _panel(
          tab,
          profile: const TextDisplayProfile(nikud: MarkVisibility.hide),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await copy.copy();
    expect(copy.text, isNull);
    copy.selectAll();
    await copy.copy();
    expect('טהור'.allMatches(copy.text!).length, 100);
    expect(copy.text, isNot(contains('טָהוֹר')));
  });

  testWidgets('טעינה מאוחרת של טווח קודם אינה חוזרת להעתקה', (tester) async {
    final pending = Completer<String>();
    _provider.contentLoader = (_) => pending.future;
    final oldTab = _bigGroupTab(100, group: 2);
    final newTab = _bigGroupTab(3, group: 3);
    addTearDown(oldTab.dispose);
    addTearDown(newTab.dispose);
    final copy = _ClipboardCapture(tester);
    await tester.pumpWidget(_wrap(_panel(oldTab)));
    await tester.pumpAndSettle();
    copy.selectAll();
    await copy.copy();
    expect(copy.text, isNull);
    _provider.contentLoader = (_) async => 'תוכן חדש';
    await tester.pumpWidget(_wrap(_panel(newTab)));
    await tester.pumpAndSettle();
    pending.complete('תוכן ישן');
    await tester.pumpAndSettle();
    copy.selectAll();
    await copy.copy();
    expect('תוכן חדש'.allMatches(copy.text!).length, 3);
    expect(copy.text, isNot(contains('תוכן ישן')));
    expect(copy.text, contains(_title(3)));
    expect(copy.text, isNot(contains(_title(2))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('קיצור מקלדת בוחר את כל הקבוצה ומעתיק טקסט HTML לפי הפרופיל', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    _provider.contentLoader = (_) async => '<b>יְהוָה</b> טָהוֹר<br>סוף';
    final tab = _bigGroupTab(100, group: 4);
    addTearDown(tab.dispose);
    final copy = _ClipboardCapture(tester);
    await tester.pumpWidget(
      _wrap(
        _panel(
          tab,
          profile: const TextDisplayProfile(nikud: MarkVisibility.hide),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<Focus>(
          find
              .descendant(
                of: find.byType(SelectableRegion).first,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Focus &&
                      widget.focusNode?.debugLabel == 'SelectableRegion',
                ),
              )
              .first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await copy.copy();
    expect('יקוק טהור סוף'.allMatches(copy.text!).length, 100);
    expect(copy.text, isNot(contains('<b>')));
    expect(copy.text, isNot(contains('<br>')));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('בחירה בזמן טעינה זמינה כשהתוכן מגיע ללא בחירה חוזרת', (
    tester,
  ) async {
    final pending = Completer<String>();
    _provider.contentLoader = (_) => pending.future;
    final tab = _bigGroupTab(100, group: 5);
    addTearDown(tab.dispose);
    final copy = _ClipboardCapture(tester);
    await tester.pumpWidget(_wrap(_panel(tab)));
    await tester.pumpAndSettle();
    copy.selectAll();
    final container = tester.widget<SelectionContainer>(
      find
          .ancestor(
            of: find.byType(ScrollablePositionedList),
            matching: find.byType(SelectionContainer),
          )
          .first,
    );
    expect(container.delegate!.getSelectedContent(), isNull);
    pending.complete('טקסט נטען');
    await tester.pumpAndSettle();
    await copy.copy();
    expect('טקסט נטען'.allMatches(copy.text!).length, 100);
    expect(tester.takeException(), isNull);
  });

  group('רשימת המפרשים של PDF בונה רק את מה שעל המסך (#844)', () {
    testWidgets('קבוצה גדולה ופתוחה אינה בונה את כל הקטעים', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tab = _bigGroupTab(300);
      addTearDown(tab.dispose);
      await tester.pumpWidget(_wrap(_panel(tab)));
      await tester.pumpAndSettle();

      final built = find
          .byType(CommentaryContent, skipOffstage: false)
          .evaluate()
          .length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));
    });

    testWidgets('"כווץ הכל" ו"הרחב הכל" משאירים בתצוגה את הקבוצה העליונה', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tab = _manyGroupsTab(groups: 60, perGroup: 5);
      addTearDown(tab.dispose);
      await tester.pumpWidget(
        _wrap(
          PdfCommentaryPanel(
            tab: tab,
            linksCount: tab.links.length,
            openBookCallback: (_) {},
            fontSize: 16,
            commentaryGroupsLoader: (links) async => [
              for (var g = 1; g <= 60; g++)
                LinkGroup(
                  bookTitle: _title(g),
                  links: [
                    for (final link in links)
                      if (link.path2 == '${_title(g)}.txt') link,
                  ],
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text(_title(20)),
        find.byType(ScrollablePositionedList).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      tester
          .state<PdfCommentaryPanelState>(find.byType(PdfCommentaryPanel))
          .toggleAllExpanded();
      await tester.pumpAndSettle();

      expect(find.text(_title(20)).hitTestable(), findsOneWidget);

      tester
          .state<PdfCommentaryPanelState>(find.byType(PdfCommentaryPanel))
          .toggleAllExpanded();
      await tester.pumpAndSettle();

      expect(find.text(_title(20)).hitTestable(), findsOneWidget);
    });
  });
}

/// [groups] commentators with [perGroup] commentaries each.
PdfBookTab _manyGroupsTab({required int groups, required int perGroup}) {
  final tab = PdfBookTab(
    book: PdfBook(title: 'ספר בדיקה', path: '/books/ספר בדיקה.pdf'),
    pageNumber: 1,
  );
  tab.currentTextLineNumber = 10;
  tab.currentTextLineNumberEnd = 40;
  tab.links = [
    for (var g = 1; g <= groups; g++)
      for (var i = 1; i <= perGroup; i++)
        Link(
          // Unlike the group header, so the header text is found once.
          heRef: '${_title(g)}, $i',
          index1: 12,
          path2: '${_title(g)}.txt',
          index2: i,
          connectionType: 'COMMENTARY',
          targetCategoryId: 1,
          targetFileType: 'txt',
        ),
  ];
  tab.activeCommentators = {for (var g = 1; g <= groups; g++) _title(g)};
  return tab;
}

PdfCommentaryPanel _panel(
  PdfBookTab tab, {
  TextDisplayProfile profile = TextDisplayProfile.defaults,
}) => PdfCommentaryPanel(
  displayProfile: profile,
  tab: tab,
  linksCount: tab.links.length,
  openBookCallback: (_) {},
  fontSize: 16,
  commentaryGroupsLoader: (links) async => [
    LinkGroup(bookTitle: tab.activeCommentators.single, links: links),
  ],
);

/// One commentator with [count] commentaries on the shown range.
PdfBookTab _bigGroupTab(int count, {int group = 1}) {
  final tab = PdfBookTab(
    book: PdfBook(title: 'ספר בדיקה', path: '/books/ספר בדיקה.pdf'),
    pageNumber: 1,
  );
  tab.currentTextLineNumber = 10;
  tab.currentTextLineNumberEnd = 40;
  tab.links = [
    for (var i = 1; i <= count; i++)
      Link(
        heRef: _title(group),
        index1: 12,
        path2: '${_title(group)}.txt',
        index2: i,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      ),
  ];
  tab.activeCommentators = {_title(group)};
  return tab;
}

Widget _wrap(Widget child) => MaterialApp(
  home: MultiBlocProvider(
    providers: [
      BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
      BlocProvider<PersonalNotesBloc>.value(value: _FakePersonalNotesBloc()),
    ],
    child: Scaffold(body: child),
  ),
);

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
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
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeLibraryProvider implements LibraryProvider {
  Future<String> Function(Link)? contentLoader;
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => const {};

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => null;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => const [];

  @override
  Future<String> getLinkContent(Link link) async => contentLoader != null
      ? await contentLoader!(link)
      : 'דְּבֵין עָמֹק בֵּין דֵּהֶה טָהוֹר.';

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      title.startsWith(_commentatorPrefix);

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}

class _ClipboardCapture {
  _ClipboardCapture(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          text = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }
  final WidgetTester tester;
  String? text;
  SelectableRegionState get region =>
      tester.state<SelectableRegionState>(find.byType(SelectableRegion).first);
  void selectAll() => region.selectAll();
  Future<void> copy() async {
    text = null;
    final actions = region.contextMenuButtonItems.where(
      (item) => item.type == ContextMenuButtonType.copy,
    );
    if (actions.isNotEmpty) actions.first.onPressed!();
    await tester.pump();
  }
}

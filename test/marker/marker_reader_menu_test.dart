import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/marker/view/reader/marker_commentary_menu.dart';
import 'package:otzaria/marker/view/reader/marker_reader_menu.dart';
import 'package:otzaria/marker/view/reader/marker_toolbar_action.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

import '../helpers/memory_settings_cache.dart';
import 'marker_test_helpers.dart';

const _lines = ['בראשית ברא אלהים את השמים ואת הארץ', 'והארץ היתה תהו ובהו'];

void main() {
  late MarkerDatabase db;
  late MarkerRepository repository;
  late MarkerBookCache previous;
  final book = TextBook(title: 'ספר בדיקה', id: 7);

  TextBookLoaded state() => TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: _lines,
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
    selectedIndex: null,
    pinLeftPane: false,
    searchText: '',
  );

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    MarkerSettings.instance.reload();
    final store = openTestMarkerStore();
    db = store.db;
    repository = store.repository;
    previous = MarkerBookCache.instance;
    MarkerBookCache.instance = MarkerBookCache(
      repository: repository,
      changes: store.changes,
    );
  });

  tearDown(() {
    MarkerBookCache.instance.dispose();
    MarkerBookCache.instance = previous;
    db.close();
  });

  Future<List<AppContextMenuEntry>> entries(
    WidgetTester tester,
    String selected,
    int startColumn,
  ) async {
    late List<AppContextMenuEntry> result;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          result = buildMarkerMenuEntries(
            context: context,
            root: null,
            state: state(),
            lines: _lines,
            paragraphIndex: 0,
            selectedText: selected,
            anchor: (
              lineStart: 0,
              lineEnd: 0,
              startColumn: startColumn,
              pointerColumn: null,
            ),
            settings: () => const RenderSettings(formatParentheses: false),
            tapPosition: Offset.zero,
          );
          return const SizedBox();
        },
      ),
    );
    return result;
  }

  testWidgets('a selection offers the menu colours of the palette', (
    tester,
  ) async {
    final menu = await entries(tester, 'אלהים', 11);
    final actions = menu.single.colorRowActions!;
    expect(actions.map((a) => a.id), [
      'yellow',
      'green',
      'blue',
      'red',
      'orange',
    ]);
  });

  testWidgets('the eraser appears only when the selection touches a mark', (
    tester,
  ) async {
    await repository.importHighlights([
      highlightFor(
        'm',
        [segmentFor(0, _lines[0], 'אלהים את')],
        book: book.title,
        uid: PluginBookIdentity.uidOf(book),
      ),
    ]);
    await MarkerBookCache.instance.ensureLoaded(
      book.title,
      PluginBookIdentity.uidOf(book),
    );

    final touching = await entries(tester, 'אלהים', 11);
    // אחרי הצבעים: המחק, ולצדו ההערה של הסימון שנבחר.
    expect(
      touching.single.colorRowActions!.reversed.take(2).map((a) => a.id),
      ['marker-note', 'marker-erase'],
    );
    expect(touching.single.colorRowActions!.last.label, 'הוספת הערה');

    final apart = await entries(tester, 'בראשית', 0);
    expect(
      apart.single.colorRowActions!.map((a) => a.id),
      isNot(contains('marker-erase')),
    );
  });

  testWidgets('the eraser leaves a mark hidden under a newer one', (
    tester,
  ) async {
    final uid = PluginBookIdentity.uidOf(book);
    await repository.importHighlights([
      highlightFor(
        'older',
        [segmentFor(0, _lines[0], 'אלהים')],
        book: book.title,
        uid: uid,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      highlightFor(
        'newer',
        [segmentFor(0, _lines[0], 'אלהים את')],
        book: book.title,
        uid: uid,
        createdAt: DateTime.utc(2026, 1, 2),
      ),
    ]);
    await MarkerBookCache.instance.ensureLoaded(book.title, uid);

    final menu = await entries(tester, 'אלהים', 11);
    final erase = menu.single.colorRowActions!.firstWhere(
      (action) => action.id == 'marker-erase',
    );
    expect(erase.label, 'מחיקת הסימון');
  });

  test('the toolbar tooltip says what a click does', () {
    final yellow = MarkerSettings.instance.palette.defaultColor;
    expect(
      markerToolbarTooltip(hasMarks: false, shown: true, color: yellow),
      'סימון הטקסט שנבחר ב${yellow.label}',
    );
    expect(
      markerToolbarTooltip(hasMarks: true, shown: true, color: yellow),
      'הסתרת הסימונים בספר',
    );
    expect(
      markerToolbarTooltip(hasMarks: true, shown: false, color: yellow),
      'הצגת הסימונים בספר',
    );
    expect(
      markerToolbarTooltip(hasMarks: false, shown: false, color: yellow),
      'הצגת הסימונים בספר',
    );
  });

  test('the commentary marker entries go before the first divider', () {
    const copy = AppContextMenuEntry(label: 'העתקה');
    const report = AppContextMenuEntry(label: 'דיווח');
    const marker = AppContextMenuEntry(label: 'מרקר');
    expect(
      withMarkerEntries(
        [
          copy,
          const AppContextMenuEntry.divider(),
          report,
        ],
        [marker],
      ).map((e) => e.label ?? '-'),
      ['העתקה', 'מרקר', '-', 'דיווח'],
    );
    expect(
      withMarkerEntries([copy], [marker]).map((e) => e.label),
      ['העתקה', 'מרקר'],
    );
    expect(withMarkerEntries([copy], const []), [copy]);
  });

  testWidgets('turning the menu off removes the entries', (tester) async {
    await MarkerSettings.instance.setShowInContextMenu(false);
    expect(await entries(tester, 'אלהים', 11), isEmpty);
  });
}

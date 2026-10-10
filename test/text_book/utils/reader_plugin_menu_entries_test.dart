import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_plugin_menu_entries.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  const lines = ['שלום עולם', 'עולם ומלואו', 'שלום לכולם'];
  const settings = RenderSettings(formatParentheses: false);

  TextBookLoaded state() => TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה', id: 7),
    showLeftPane: false,
    content: lines,
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
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );

  test('זהות ספר ללא סימון כוללת את הפסקה שנלחצה ולא טווח מומצא', () {
    final payload = buildReaderBookPayload(state: state(), paragraphIndex: 2);
    expect(payload['id'], 7);
    expect(payload['bookId'], 'ספר בדיקה');
    expect(payload['currentBookId'], 'ספר בדיקה');
    expect(payload['bookTitle'], 'ספר בדיקה');
    expect(payload['type'], 'text');
    expect(payload['source'], 'library');
    expect(payload['bookUid'], isNotEmpty);
    expect(payload['sectionIndex'], 2);
    expect(payload['currentIndex'], 2);
    expect(payload['text'], isEmpty);
    expect(payload['start'], isNull);
    expect(payload['end'], isNull);
    expect(payload.containsKey('sourceRange'), isFalse);
  });

  group('buildReaderSelectionPayload', () {
    for (final (startColumn, pointerColumn) in [
      (0, 2),
      (0, 4),
      (0, 5),
      (5, 4),
      (5, 7),
    ]) {
      test(
        'tracked start $startColumn wins over pointer $pointerColumn in repeated text',
        () {
          final payload = buildReaderSelectionPayload(
            state: state(),
            lines: const ['שלום שלום'],
            paragraphIndex: 0,
            selectedText: 'שלום',
            anchor: (
              lineStart: 0,
              lineEnd: 0,
              startColumn: startColumn,
              pointerColumn: pointerColumn,
            ),
            settings: settings,
          );
          expect(payload['start'], startColumn);
          expect(payload['end'], startColumn + 4);
        },
      );
    }

    test('anchors a selection in the paragraph where it starts', () {
      final payload = buildReaderSelectionPayload(
        state: state(),
        lines: lines,
        paragraphIndex: 2,
        selectedText: 'עולם',
        anchor: (lineStart: 1, lineEnd: 1, startColumn: 0, pointerColumn: 8),
        settings: settings,
      );

      expect(payload['currentIndex'], 1);
      expect(payload['text'], 'עולם');
      expect(payload['id'], 7);
      expect(payload.containsKey('sections'), isFalse);
    });

    test('falls back to the clicked paragraph without a tracked start', () {
      final payload = buildReaderSelectionPayload(
        state: state(),
        lines: lines,
        paragraphIndex: 2,
        selectedText: 'שלום',
        anchor: (
          lineStart: null,
          lineEnd: null,
          startColumn: null,
          pointerColumn: null,
        ),
        settings: settings,
      );

      expect(payload['currentIndex'], 2);
    });

    test('gives a selection over paragraphs one anchor per paragraph', () {
      final payload = buildReaderSelectionPayload(
        state: state(),
        lines: lines,
        paragraphIndex: 0,
        selectedText: 'עולם\nעולם ומלואו',
        anchor: (lineStart: 0, lineEnd: 1, startColumn: 5, pointerColumn: 5),
        settings: settings,
      );

      expect(payload['currentIndex'], 0);
      final sections = payload['sections'] as List;
      expect([for (final s in sections) s['currentIndex']], [0, 1]);
    });
  });

  group('buildReaderPluginMenuEntries', () {
    const items = [
      (
        'plugin.a',
        PluginContextMenuItem(
          id: 'text',
          label: 'בטקסט',
          contexts: ['reader-selection'],
        ),
      ),
      (
        'plugin.b',
        PluginContextMenuItem(
          id: 'page',
          label: 'בצורת הדף',
          contexts: ['reader-page-shape-selection'],
        ),
      ),
    ];

    Future<List<String?>> labels(
      WidgetTester tester, {
      required bool hasSelection,
      String? selectionContext,
      List<(String, PluginContextMenuItem)> pluginItems = items,
      int paragraphIndex = 0,
    }) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      var settingsCalls = 0;
      final entries = buildReaderPluginMenuEntries(
        root: null,
        state: state(),
        lines: lines,
        paragraphIndex: paragraphIndex,
        hasSelection: hasSelection,
        selectedText: hasSelection ? 'שלום' : null,
        anchor: (
          lineStart: null,
          lineEnd: null,
          startColumn: null,
          pointerColumn: null,
        ),
        settings: () {
          settingsCalls++;
          return settings;
        },
        tapPosition: Offset.zero,
        menuContext: context,
        selectionContext: selectionContext ?? 'reader-selection',
        pluginItems: pluginItems,
      );
      if (pluginItems.isEmpty) expect(settingsCalls, 0);
      return [for (final e in entries) e.isDivider ? '---' : e.label];
    }

    testWidgets('a selection shows the items of the given context', (
      tester,
    ) async {
      expect(await labels(tester, hasSelection: true), ['---', 'בטקסט']);
      expect(
        await labels(
          tester,
          hasSelection: true,
          selectionContext: 'reader-page-shape-selection',
        ),
        ['---', 'בצורת הדף'],
      );
    });

    testWidgets('without plugin items or outside the text it is empty', (
      tester,
    ) async {
      expect(
        await labels(tester, hasSelection: true, pluginItems: const []),
        isEmpty,
      );
      expect(
        await labels(tester, hasSelection: true, paragraphIndex: 3),
        isEmpty,
      );
    });

    testWidgets('פעולת ספר מוצגת ללא סימון בשני הקוראים', (tester) async {
      const bookItems = [
        (
          'plugin.book',
          PluginContextMenuItem(
            id: 'correct-book',
            label: 'העבר את הספר לתיקון',
            contexts: ['reader-book'],
          ),
        ),
        (
          'plugin.selection',
          PluginContextMenuItem(id: 'selection', label: 'פעולה על סימון'),
        ),
      ];
      for (final context in [
        'reader-selection',
        'reader-page-shape-selection',
      ]) {
        expect(
          await labels(
            tester,
            hasSelection: false,
            selectionContext: context,
            pluginItems: bookItems,
          ),
          ['---', 'העבר את הספר לתיקון'],
        );
      }
    });

    testWidgets('סימון פעיל מציג פעולות סימון בלבד גם כשנרשמו פעולות ספר', (
      tester,
    ) async {
      expect(
        await labels(
          tester,
          hasSelection: true,
          pluginItems: const [
            (
              'plugin.book',
              PluginContextMenuItem(
                id: 'book',
                label: 'פעולת ספר',
                contexts: ['reader-book'],
              ),
            ),
            (
              'plugin.selection',
              PluginContextMenuItem(
                id: 'selection',
                label: 'פעולת סימון',
                contexts: ['reader-selection'],
              ),
            ),
            (
              'plugin.highlight',
              PluginContextMenuItem(
                id: 'highlight',
                label: 'פעולת הדגשה',
                contexts: ['reader-highlight'],
              ),
            ),
          ],
        ),
        ['---', 'פעולת סימון'],
      );
    });

    testWidgets('פעולות ספר והדגשה קיימת מוצגות יחד ללא סימון', (tester) async {
      const owner = 'reader-menu-highlight-test';
      final selection = buildReaderSelectionPayload(
        state: state(),
        lines: lines,
        paragraphIndex: 0,
        selectedText: 'שלום עולם',
        anchor: (lineStart: 0, lineEnd: 0, startColumn: 0, pointerColumn: 0),
        settings: settings,
      );
      PluginHighlightRegistry.instance.setHighlight(
        ownerPluginId: owner,
        payload: {
          'bookId': state().book.title,
          'sectionIndex': 0,
          'range': selection['sourceRange'],
          'style': {'backgroundColor': '#FFE066'},
        },
      );
      addTearDown(
        () => PluginHighlightRegistry.instance.clearAll(ownerPluginId: owner),
      );
      late BuildContext context;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (c) {
              context = c;
              return const Center(
                child: Text('שלום עולם', style: TextStyle(fontSize: 24)),
              );
            },
          ),
        ),
      );
      final entries = buildReaderPluginMenuEntries(
        root: tester.renderObject(find.text('שלום עולם')),
        state: state(),
        lines: lines,
        paragraphIndex: 0,
        hasSelection: false,
        selectedText: null,
        anchor: (
          lineStart: null,
          lineEnd: null,
          startColumn: null,
          pointerColumn: null,
        ),
        settings: () => settings,
        tapPosition: tester.getCenter(find.text('שלום עולם')),
        menuContext: context,
        pluginItems: const [
          (
            'plugin.book',
            PluginContextMenuItem(
              id: 'book',
              label: 'פעולת ספר',
              contexts: ['reader-book'],
            ),
          ),
          (
            owner,
            PluginContextMenuItem(
              id: 'highlight',
              label: 'פעולת הדגשה',
              contexts: ['reader-highlight'],
            ),
          ),
        ],
      );
      expect(
        [for (final entry in entries) entry.isDivider ? '---' : entry.label],
        ['---', 'פעולת ספר', '---', 'פעולת הדגשה'],
      );
    });
    testWidgets('without a selection only a clicked highlight counts', (
      tester,
    ) async {
      expect(await labels(tester, hasSelection: false), isEmpty);
    });
  });
}

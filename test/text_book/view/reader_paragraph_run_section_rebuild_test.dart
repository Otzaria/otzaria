import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';

const _text = 'ראש טקסט סוף';
const _bookTitle = 'גיטין';
const _pluginId = 'plugin.paragraph.rebuild.test';

Map<String, dynamic> _payload({required String id, required int section}) => {
  'highlightId': id,
  'bookId': _bookTitle,
  'sectionIndex': section,
  'range': {
    'type': 'text-range-v1',
    'schemaVersion': 1,
    'sourceTextHash':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'layer': 'source',
    'start': {'grapheme': 4, 'codePoint': 4, 'utf16': 4},
    'end': {'grapheme': 8, 'codePoint': 8, 'utf16': 8},
    'exactText': 'טקסט',
    'beforeText': {
      'raw': 'ראש ',
      'normalized': 'ראש ',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'afterText': {
      'raw': ' סוף',
      'normalized': ' סוף',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'occurrenceIndexInSection': 0,
    'occurrenceCountInSection': 1,
  },
  'style': {'backgroundColor': '#FFE066'},
};

/// פסקה רציפה אחת לכל שורה, כדי לראות איזו פסקה נבנית מחדש.
Widget _paragraphs(int count, {bool isMainText = true}) {
  final lines = List.filled(count, _text);
  final lineContext = ReaderLineContext(
    state: TextBookLoaded(
      book: TextBook(title: _bookTitle),
      showLeftPane: false,
      content: lines,
      fontSize: 20,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      visibleIndices: const [0],
      pinLeftPane: false,
      searchText: '',
    ),
    lines: lines,
    profile: TextDisplayProfile.defaults,
    lineHtml: (index) => lines[index],
    fontSize: 20,
    lineHeight: 1.5,
    isMainText: isMainText,
  );
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          for (var i = 0; i < count; i++)
            ReaderParagraphRun(
              specs: [buildReaderLineSpec(i, lineContext)],
              lineContext: lineContext,
              onTapUrl: (_) async => true,
            ),
        ],
      ),
    ),
  );
}

final _rebuiltSections = <int>{};

void _onRebuild(Element element, bool builtOnce) {
  if (element.widget is! ListenableBuilder) return;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is! ReaderParagraphRun) return true;
    _rebuiltSections.add(widget.specs.single.lineIndex);
    return false;
  });
}

Set<int> _takeRebuilt() {
  final result = Set.of(_rebuiltSections);
  _rebuiltSections.clear();
  return result;
}

void main() {
  setUp(() {
    PluginHighlightRegistry.instance.removePlugin(_pluginId);
    PluginHighlightRevealService.instance.clear();
    _rebuiltSections.clear();
    debugOnRebuildDirtyWidget = _onRebuild;
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
    PluginHighlightRevealService.instance.clear();
    PluginHighlightRegistry.instance.removePlugin(_pluginId);
  });

  testWidgets('הדגשה בונה מחדש רק את הפסקה של הקטע שלה', (tester) async {
    await tester.pumpWidget(_paragraphs(5));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h2', section: 2),
    );
    await tester.pumpAndSettle();
    expect(_takeRebuilt(), {2});

    PluginHighlightRegistry.instance.removePlugin(_pluginId);
    await tester.pumpAndSettle();
    expect(_takeRebuilt(), {2});
  });

  testWidgets('חשיפת הדגשה בונה מחדש רק את הפסקה שלה, בכניסה וביציאה', (
    tester,
  ) async {
    final highlight = PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h3', section: 3),
    );
    await tester.pumpWidget(_paragraphs(5));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRevealService.instance.reveal(highlight);
    await tester.pump();
    expect(_takeRebuilt(), {3});

    PluginHighlightRevealService.instance.clear();
    await tester.pump();
    expect(_takeRebuilt(), {3});
  });

  testWidgets('טקסט שאינו הספר הראשי אינו מאזין להדגשות התוספים', (
    tester,
  ) async {
    await tester.pumpWidget(_paragraphs(3, isMainText: false));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h1', section: 1),
    );
    await tester.pumpAndSettle();
    expect(_takeRebuilt(), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/reader_section_content_tracker.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  late List<Map<String, dynamic>> events;
  late ReaderSectionContentTracker tracker;

  setUp(() {
    events = [];
    tracker = ReaderSectionContentTracker.forTesting(
      dispatchEvent: (topic, payload) async {
        expect(topic, 'reader.sectionContentChanged');
        events.add(payload);
      },
    );
  });

  test('first and identical snapshots do not emit an event', () async {
    await tracker.recordSnapshot(
      bookId: 'book',
      sectionIndex: 4,
      sourceText: 'source',
      renderedText: 'rendered',
    );
    await tracker.recordSnapshot(
      bookId: 'book',
      sectionIndex: 4,
      sourceText: 'source',
      renderedText: 'rendered',
    );

    expect(events, isEmpty);
  });

  test('source change emits source-content with old and new hashes', () async {
    await tracker.recordSnapshot(
      bookId: 'book',
      sectionIndex: 4,
      sourceText: 'old source',
      renderedText: 'old rendered',
    );
    final change = await tracker.recordSnapshot(
      bookId: 'book',
      sectionIndex: 4,
      sourceText: 'new source',
      renderedText: 'new rendered',
      reason: 'book-updated',
    );

    expect(change?.changeType, 'source-content');
    expect(events, hasLength(1));
    expect(events.single['schemaVersion'], 1);
    expect(events.single['oldSourceTextHash'], isNotEmpty);
    expect(events.single['newSourceTextHash'], isNotEmpty);
    expect(
      events.single['oldSourceTextHash'],
      isNot(events.single['newSourceTextHash']),
    );
    expect(events.single['reason'], 'book-updated');
  });

  test(
    'rendered-only change keeps source hash and classifies reason',
    () async {
      await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'with nikud',
      );
      final change = await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'without nikud',
        reason: 'nikud-toggle',
      );

      expect(change?.changeType, 'rendering-only');
      expect(
        events.single['oldSourceTextHash'],
        events.single['newSourceTextHash'],
      );
      expect(
        events.single['oldRenderedTextHash'],
        isNot(events.single['newRenderedTextHash']),
      );
      expect(events.single['reason'], 'nikud-toggle');
    },
  );

  test(
    'render settings change emits when rendered text is identical',
    () async {
      await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'rendered',
        renderingSignature: 'font-a:18',
      );
      final change = await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'rendered',
        renderingSignature: 'font-b:20',
        reason: 'font-render-change',
      );

      expect(change?.changeType, 'rendering-only');
      expect(events, hasLength(1));
      expect(
        events.single['oldRenderedTextHash'],
        events.single['newRenderedTextHash'],
      );
      expect(events.single['reason'], 'font-render-change');
    },
  );

  test(
    'transient search navigation does not change the rendering signature',
    () async {
      const initialSettings = RenderSettings(
        searchText: 'query',
        currentSearchIndex: 0,
        searchOptions: {
          'query': {'exact': true},
        },
        highlightYellowBackground: false,
      );
      const navigatedSettings = RenderSettings(
        searchText: 'other query',
        currentSearchIndex: -1,
        searchOptions: {
          'query': {'exact': false},
        },
        alternativeWords: {
          0: ['alternate'],
        },
        spacingValues: {'0': '2'},
        isFuzzySearch: true,
        highlightYellowBackground: true,
        partialWordHighlight: true,
      );

      await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'rendered',
        renderingSignature: initialSettings.sectionContentRenderingSignature,
      );
      final change = await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'rendered',
        renderingSignature: navigatedSettings.sectionContentRenderingSignature,
      );

      expect(change, isNull);
      expect(events, isEmpty);
    },
  );

  test(
    'persistent typography change updates the rendering signature',
    () async {
      const initialSettings = RenderSettings(fontSize: 18, fontFamily: 'A');
      const changedSettings = RenderSettings(fontSize: 20, fontFamily: 'B');

      await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'rendered',
        renderingSignature: initialSettings.sectionContentRenderingSignature,
      );
      final change = await tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 4,
        sourceText: 'source',
        renderedText: 'rendered',
        renderingSignature: changedSettings.sectionContentRenderingSignature,
        reason: 'font-render-change',
      );

      expect(change?.changeType, 'rendering-only');
      expect(events, hasLength(1));
    },
  );

  test('snapshots are isolated by book and section', () async {
    await tracker.recordSnapshot(
      bookId: 'book-a',
      sectionIndex: 1,
      sourceText: 'one',
    );
    await tracker.recordSnapshot(
      bookId: 'book-b',
      sectionIndex: 1,
      sourceText: 'two',
    );
    await tracker.recordSnapshot(
      bookId: 'book-a',
      sectionIndex: 2,
      sourceText: 'three',
    );

    expect(events, isEmpty);
  });

  test('forgetBook causes the next snapshot to become a baseline', () async {
    await tracker.recordSnapshot(
      bookId: 'book',
      sectionIndex: 1,
      sourceText: 'old',
    );
    tracker.forgetBook('book');
    await tracker.recordSnapshot(
      bookId: 'book',
      sectionIndex: 1,
      sourceText: 'new',
    );

    expect(events, isEmpty);
  });

  test('rejects an unsupported reason before changing the baseline', () async {
    await expectLater(
      tracker.recordSnapshot(
        bookId: 'book',
        sectionIndex: 1,
        sourceText: 'source',
        reason: 'unknown',
      ),
      throwsArgumentError,
    );
    await tracker.recordSnapshot(
      bookId: 'book',
      sectionIndex: 1,
      sourceText: 'source',
    );

    expect(events, isEmpty);
  });
}

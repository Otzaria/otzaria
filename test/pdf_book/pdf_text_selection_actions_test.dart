import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_text_selection_actions.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Document document;
  late _Selection selection;
  late _Controller controller;
  late PdfTextSelectionActions actions;
  late List<String> writes;
  late bool active;
  late int activeChecks;
  Completer<void>? clipboardWrite;

  setUp(() {
    document = _Document(3);
    selection = _Selection()..range = _range(1, 3);
    controller = _Controller(document, selection);
    active = true;
    activeChecks = 0;
    actions = PdfTextSelectionActions(
      controller,
      isActive: () {
        activeChecks++;
        return active;
      },
    );
    addTearDown(actions.releaseSelectedTextSnapshot);
    writes = [];
    clipboardWrite = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            writes.add((call.arguments as Map)['text'] as String);
            await clipboardWrite?.future;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'menu copy waits for the platform before succeeding or clearing',
    () async {
      clipboardWrite = Completer<void>();
      var completed = false;
      final copy = actions.copy().then((result) {
        completed = true;
        return result;
      });
      await _flush();
      expect(writes, ['Page textPage textPag']);
      expect(completed, isFalse);
      expect(selection.hasSelectedText, isTrue);
      clipboardWrite!.complete();
      expect(await copy, PdfTextActionResult.copied);
      expect(selection.hasSelectedText, isFalse);
    },
  );

  test('clipboard failure keeps the selection and returns failure', () async {
    clipboardWrite = Completer<void>();
    final copy = actions.copy();
    await _flush();
    clipboardWrite!.completeError(PlatformException(code: 'clipboard-denied'));
    expect(await copy, PdfTextActionResult.failed);
    expect(selection.hasSelectedText, isTrue);
  });

  test('keyboard copy preserves the selection', () async {
    final range = selection.range;
    expect(await actions.copy(keepSelection: true), PdfTextActionResult.copied);
    expect(selection.range, same(range));
    expect(writes, ['Page textPage textPag']);
  });

  test(
    'empty, disabled and forbidden selections do not touch the clipboard',
    () async {
      selection.range = null;
      expect(await actions.copy(), PdfTextActionResult.none);
      selection.range = _range(1, 3);
      selection.isCopyAllowed = false;
      expect(await actions.copy(), PdfTextActionResult.none);
      selection.isCopyAllowed = true;
      selection.isTextSelectionEnabled = false;
      expect(await actions.copy(), PdfTextActionResult.none);
      expect(await actions.selectAll(), PdfTextActionResult.none);
      expect(selection.reads, 0);
      expect(writes, isEmpty);
    },
  );

  test('copy refuses a range with an unloaded middle page', () async {
    document.pages[1].isLoaded = false;
    expect(await actions.copy(), PdfTextActionResult.loading);
    expect(selection.reads, 0);
    expect(writes, isEmpty);
  });

  for (final change in [
    'cancel',
    'hidden',
    'detached',
    'document',
    'selection',
    'permission',
    'page-content',
  ]) {
    void invalidate() {
      switch (change) {
        case 'cancel':
          actions.cancel();
        case 'hidden':
          active = false;
        case 'detached':
          controller.isReady = false;
        case 'document':
          controller.document = _Document(2);
        case 'selection':
          selection.range = _range(2, 2);
        case 'permission':
          selection.isCopyAllowed = false;
        case 'page-content':
          document.pages = [...document.pages]..[1] = _Page(2);
      }
    }

    test('copy stops after a pending text read when $change changes', () async {
      final text = Completer<PdfPageText>();
      document.pages[1].load = () => text.future;
      final copy = actions.copy();
      await _flush();
      invalidate();
      text.complete(_text(2, 'stale text'));
      expect(await copy, PdfTextActionResult.none);
      expect(writes, isEmpty);
      expect(selection.clears, 0);
    });

    if (change == 'permission' || change == 'page-content') continue;

    test(
      'pending select-all stops before another page or mutation on $change',
      () async {
        selection.range = null;
        final first = Completer<PdfPageText>();
        document.pages.first.load = () => first.future;
        final select = actions.selectAll();
        await _flush();
        invalidate();
        first.complete(_text(1));
        expect(await select, PdfTextActionResult.none);
        expect(document.pages.map((page) => page.reads).toList(), [1, 0, 0]);
        expect(selection.updates, 0);
      },
    );
  }

  test('a late clipboard response leaves a new selection intact', () async {
    clipboardWrite = Completer<void>();
    final copy = actions.copy();
    await _flush();
    final newRange = selection.range = _range(2, 2);
    clipboardWrite!.complete();
    expect(await copy, PdfTextActionResult.none);
    expect(selection.range, same(newRange));
    expect(selection.clears, 0);
  });

  test(
    'select-all refuses a partial progressive load and works on retry',
    () async {
      final previousRange = selection.range = _range(1, 1);
      document.pages[1].isLoaded = false;
      expect(await actions.selectAll(), PdfTextActionResult.loading);
      expect(selection.range, same(previousRange));
      expect(document.pages.every((page) => page.reads == 0), isTrue);
      document.pages[1].isLoaded = true;
      expect(await actions.selectAll(), PdfTextActionResult.none);
      expect(selection.range!.start.text.pageNumber, 1);
      expect(selection.range!.start.index, 0);
      expect(selection.range!.end.text.pageNumber, 3);
      expect(selection.range!.end.index, _text(3).charRects.length - 1);
      expect(document.pages.map((page) => page.reads).toList(), [1, 0, 1]);
    },
  );

  test(
    'select-all skips blank edge pages without reading every text page',
    () async {
      controller.document = document = _Document(500);
      document.pages.first.load = () async => _text(1, '');
      document.pages.last.load = () async => _text(500, '');
      selection.range = null;
      await actions.selectAll();
      expect(selection.range!.start.text.pageNumber, 2);
      expect(selection.range!.end.text.pageNumber, 499);
      expect(document.pages.fold(0, (total, page) => total + page.reads), 4);
    },
  );

  test(
    'repeated select-all coalesces pending text and applies only the latest',
    () async {
      selection.range = null;
      final first = Completer<PdfPageText>();
      document.pages.first.load = () => first.future;
      final firstSelection = actions.selectAll();
      await _flush();
      final secondSelection = actions.selectAll();
      await _flush();
      first.complete(_text(1));
      await Future.wait([firstSelection, secondSelection]);
      expect(document.pages.map((page) => page.reads).toList(), [1, 0, 1]);
      expect(selection.updates, 1);
    },
  );

  test(
    'extraction failure is handled without changing the selection',
    () async {
      document.pages.first.load = () => Future.error(StateError('closed PDF'));
      expect(await actions.selectAll(), PdfTextActionResult.failed);
      expect(selection.updates, 0);
      document.pages[1].load = () => Future.error(StateError('closed PDF'));
      expect(await actions.copy(), PdfTextActionResult.failed);
      expect(writes, isEmpty);
      expect(selection.clears, 0);
    },
  );

  test(
    'same-page backward selection preserves Hebrew, accents and spaces',
    () async {
      const content = 'אבג שָׁלוֹם  ABC\nדהו';
      final page = _text(1, content);
      selection.range = PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(page, content.length - 3),
        PdfTextSelectionPoint(page, 2),
      );
      expect(
        await actions.readSelectedText(),
        content.substring(2, content.length - 2),
      );
      expect(
        await actions.copy(keepSelection: true),
        PdfTextActionResult.copied,
      );
      expect(writes.single, content.substring(2, content.length - 2));
      expect(document.pages.every((page) => page.reads == 0), true);
      expect(selection.reads, 0);
    },
  );

  test(
    'page order and blank middle pages match the inclusive selection',
    () async {
      controller.document = document = _Document(5);
      selection.range = PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(_text(5, 'END suffix'), 2),
        PdfTextSelectionPoint(_text(1, 'prefix START\n'), 7),
      );
      document.pages[1].load = () async => _text(2, 'אבג\n');
      document.pages[2].load = () async => _text(3, '');
      document.pages[3].load = () async => _text(4, 'שָׁלוֹם  ABC ');
      // Keep the library's existing normalization of raw-page whitespace.
      final formatted = await (_Page(
        4,
      )..load = document.pages[3].load).loadStructuredText();
      expect(
        await actions.readSelectedText(),
        'START\nאבג\n${formatted.fullText}END',
      );
      expect(document.pages.map((page) => page.reads), [0, 1, 1, 1, 0]);
      expect(PdfPageTextCache.forDocument(document).length, 0);
      expect(selection.reads, 0);
    },
  );

  test(
    'a stale cached middle page is neither reused nor replaced by a read',
    () async {
      final cache = PdfPageTextCache.forDocument(document);
      document.pages[1].load = () async => _text(2, 'old content');
      final stale = await cache.load(document.pages[1]);
      final lease = cache.createLease()..updatePinnedPages([2]);
      addTearDown(lease.dispose);
      final bytes = cache.estimatedBytes;
      document.pages = [...document.pages]
        ..[1] = (_Page(2)..load = () async => _text(2, 'new content'));
      expect(await actions.readSelectedText(), 'Page textnew contentPag');
      expect(cache.length, 1);
      expect(cache.estimatedBytes, bytes);
      expect(cache.get(2), same(stale));
      expect(document.pages[1].reads, 1);
    },
  );

  test('read cancellation stops before another middle page', () async {
    controller.document = document = _Document(5);
    selection.range = _range(1, 5);
    final pending = Completer<PdfPageText>();
    document.pages[1].load = () => pending.future;
    final read = actions.readSelectedText();
    await _flush();
    actions.cancel();
    pending.complete(_text(2));
    expect(await read, isNull);
    expect(document.pages.map((page) => page.reads), [0, 1, 0, 0, 0]);
    expect(selection.range, isNotNull);
    expect(writes, isEmpty);
  });

  test(
    'a replacement during a pending read cannot reach its consumer',
    () async {
      final pending = Completer<PdfPageText>();
      document.pages[1].load = () => pending.future;
      final read = actions.readSelectedText();
      await _flush();
      document.pages = [...document.pages]..[1] = _Page(2);
      pending.complete(_text(2));
      expect(await read, isNull);
      expect(writes, isEmpty);
    },
  );

  test(
    'metadata updates outside the selection do not cancel its read',
    () async {
      controller.document = document = _Document(20);
      final pending = Completer<PdfPageText>();
      document.pages[1].load = () => pending.future;
      final read = actions.readSelectedText();
      await _flush();
      document.pages = [...document.pages]..[19] = _Page(20);
      pending.complete(_text(2, 'current text'));
      expect(await read, 'Page textcurrent textPag');
      expect(document.pages[1].reads, 1);
      expect(document.pages[19].reads, 0);
    },
  );

  test('metadata updates outside the selection do not cancel Copy', () async {
    controller.document = document = _Document(20);
    final pending = Completer<PdfPageText>();
    document.pages[1].load = () => pending.future;
    final copy = actions.copy(keepSelection: true);
    await _flush();
    document.pages = [...document.pages]..[19] = _Page(20);
    pending.complete(_text(2, 'current text'));
    expect(await copy, PdfTextActionResult.copied);
    expect(writes, ['Page textcurrent textPag']);
  });

  test(
    'a late extraction failure after cancellation is not sent to consumers',
    () async {
      final pending = Completer<PdfPageText>();
      document.pages[1].load = () => pending.future;
      final read = actions.readSelectedText();
      await _flush();
      actions.cancel();
      pending.completeError(StateError('document closed'));
      expect(await read, isNull);
      expect(writes, isEmpty);
    },
  );

  test('a newer read supersedes an older pending copy', () async {
    final pending = Completer<PdfPageText>();
    document.pages[1].load = () => pending.future;
    final copy = actions.copy();
    await _flush();
    selection.range = _range(1, 1);
    expect(await actions.readSelectedText(), 'Pag');
    pending.complete(_text(2));
    expect(await copy, PdfTextActionResult.none);
    expect(writes, isEmpty);
    expect(selection.clears, 0);
  });

  test(
    'lazy search ignores missing middle pages and retries them later',
    () async {
      document.pages[1].isLoaded = false;
      expect(
        await actions.readSelectedText(requireCopyPermission: false),
        'Page textPag',
      );
      expect(actions.selectedTextSnapshot, isNull);
      expect(document.pages[1].reads, 0);
      expect(document._events.hasListener, isFalse);

      document.pages[1].isLoaded = true;
      expect(
        await actions.readSelectedText(requireCopyPermission: false),
        'Page textPage textPag',
      );
      expect(actions.selectedTextSnapshot, 'Page textPage textPag');
      expect(document.pages[1].reads, 1);
    },
  );

  test(
    'restricted documents retain search but withhold text from plugins and Copy',
    () async {
      selection.isCopyAllowed = false;
      expect(await actions.readSelectedText(), isNull);
      expect(await actions.copy(), PdfTextActionResult.none);
      expect(document.pages[1].reads, 0);

      expect(
        await actions.readSelectedText(requireCopyPermission: false),
        'Page textPage textPag',
      );
      expect(actions.selectedTextSnapshot, 'Page textPage textPag');
      expect(await actions.readSelectedText(), isNull);
      expect(await actions.copy(), PdfTextActionResult.none);
      expect(writes, isEmpty);
    },
  );

  test(
    'document events discard a silently cleared snapshot before another read',
    () async {
      expect(await actions.readSelectedText(), 'Page textPage textPag');
      selection.range = null;
      document._events.add(
        PdfDocumentPageStatusChangedEvent(
          document,
          changes: {2: PdfPageStatusModified(page: document.pages[1])},
        ),
      );
      await _flush();

      activeChecks = 0;
      expect(actions.selectedTextSnapshot, isNull);
      expect(activeChecks, 0, reason: 'the event already released the guard');
      expect(document._events.hasListener, isFalse);
    },
  );

  test('page replacement eagerly drops the retained snapshot', () async {
    expect(await actions.readSelectedText(), 'Page textPage textPag');
    document.pages = [...document.pages]..[1] = _Page(2);
    document._events.add(
      PdfDocumentPageStatusChangedEvent(
        document,
        changes: {2: PdfPageStatusModified(page: document.pages[1])},
      ),
    );
    await _flush();

    activeChecks = 0;
    expect(actions.selectedTextSnapshot, isNull);
    expect(activeChecks, 0, reason: 'the event already released the guard');
    expect(document._events.hasListener, isFalse);
    expect(await actions.readSelectedText(), 'Page textPage textPag');
    expect(document.pages[1].reads, 1);
  });

  test('old document events release its snapshot after replacement', () async {
    expect(await actions.readSelectedText(), 'Page textPage textPag');
    controller.document = _Document(3);
    document._events.add(PdfDocumentLoadCompleteEvent(document));
    await _flush();

    activeChecks = 0;
    expect(actions.selectedTextSnapshot, isNull);
    expect(activeChecks, 0, reason: 'the event already released the guard');
    expect(document._events.hasListener, isFalse);
  });

  test(
    'explicit release detaches the old document before a new read',
    () async {
      expect(await actions.readSelectedText(), 'Page textPage textPag');
      expect(document._events.hasListener, isTrue);
      final oldDocument = document;
      actions.cancel();
      actions.releaseSelectedTextSnapshot();
      actions.releaseSelectedTextSnapshot();
      expect(oldDocument._events.hasListener, isFalse);

      controller.document = document = _Document(3);
      expect(await actions.readSelectedText(), 'Page textPage textPag');
      oldDocument._events.add(PdfDocumentLoadCompleteEvent(oldDocument));
      await oldDocument._events.close();
      expect(actions.selectedTextSnapshot, 'Page textPage textPag');
      expect(document._events.hasListener, isTrue);
      expect(document.pages[1].reads, 1);
    },
  );

  test(
    'replayed events and metadata outside the selection keep text reusable',
    () async {
      controller.document = document = _Document(20);
      document._events.onListen = () => document._events.add(
        PdfDocumentPageStatusChangedEvent(
          document,
          changes: {2: PdfPageStatusModified(page: document.pages[1])},
        ),
      );
      expect(await actions.readSelectedText(), 'Page textPage textPag');
      await _flush();
      expect(actions.selectedTextSnapshot, 'Page textPage textPag');

      document.pages = [...document.pages]..[19] = _Page(20);
      document._events.add(
        PdfDocumentPageStatusChangedEvent(
          document,
          changes: {20: PdfPageStatusModified(page: document.pages[19])},
        ),
      );
      await _flush();
      actions.cancel();
      expect(
        await actions.copy(keepSelection: true),
        PdfTextActionResult.copied,
      );
      expect(writes, ['Page textPage textPag']);
      expect(document.pages[1].reads, 1);
      expect(document.pages[19].reads, 0);
      expect(document._events.hasListener, isTrue);

      selection.range = _range(1, 1);
      actions.discardStaleSnapshot();
      expect(document._events.hasListener, isFalse);
    },
  );

  test('closing the document releases its retained snapshot', () async {
    expect(await actions.readSelectedText(), 'Page textPage textPag');
    await document._events.close();
    activeChecks = 0;
    expect(actions.selectedTextSnapshot, isNull);
    expect(activeChecks, 0);
  });

  test(
    'repeat Copy reuses plain text until the selection or page changes',
    () async {
      expect(
        await actions.copy(keepSelection: true),
        PdfTextActionResult.copied,
      );
      expect(actions.selectedTextSnapshot, writes.single);
      actions.cancel();
      expect(
        await actions.copy(keepSelection: true),
        PdfTextActionResult.copied,
      );
      expect(writes, ['Page textPage textPag', 'Page textPage textPag']);
      expect(document.pages[1].reads, 1);

      document.pages = [...document.pages]
        ..[1] = (_Page(2)..load = () async => _text(2, 'new content'));
      expect(actions.selectedTextSnapshot, isNull);
      expect(await actions.readSelectedText(), 'Page textnew contentPag');

      selection.range = _range(1, 1);
      expect(actions.selectedTextSnapshot, isNull);
      expect(await actions.readSelectedText(), 'Pag');

      controller.document = _Document(3);
      expect(actions.selectedTextSnapshot, isNull);
    },
  );

  test('failed text extraction remains an error for the consumer', () async {
    document.pages[1].load = () => Future.error(StateError('closed PDF'));
    await expectLater(actions.readSelectedText(), throwsStateError);
    expect(writes, isEmpty);
    expect(selection.clears, 0);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

PdfPageText _text(int page, [String content = 'Page text']) => PdfPageText(
  pageNumber: page,
  fullText: content,
  charRects: List.filled(content.length, const PdfRect(0, 10, 10, 0)),
  fragments: const [],
);

PdfTextSelectionRange _range(int start, int end) =>
    PdfTextSelectionRange.fromPoints(
      PdfTextSelectionPoint(_text(start), 0),
      PdfTextSelectionPoint(_text(end), 2),
    );

class _Controller extends Fake implements PdfViewerController {
  _Controller(this.document, this.textSelectionDelegate);
  @override
  PdfDocument document;
  @override
  final PdfTextSelectionDelegate textSelectionDelegate;
  @override
  bool isReady = true;
}

class _Selection extends Fake implements PdfTextSelectionDelegate {
  PdfTextSelectionRange? range;
  int reads = 0;
  int updates = 0;
  int clears = 0;
  Future<String> Function() readText = () async => 'selected text';
  @override
  bool isCopyAllowed = true;
  @override
  bool isTextSelectionEnabled = true;
  @override
  bool get hasSelectedText => range != null;
  @override
  PdfTextSelectionRange? get textSelectionPointRange => range;
  @override
  Future<String> getSelectedText() {
    reads++;
    return readText();
  }

  @override
  Future<void> clearTextSelection() async {
    clears++;
    range = null;
  }

  @override
  Future<void> setTextSelectionPointRange(PdfTextSelectionRange value) async {
    updates++;
    range = value;
  }
}

class _Document extends Fake implements PdfDocument {
  _Document(int count) : _pages = List.generate(count, (i) => _Page(i + 1)) {
    addTearDown(_events.close);
  }
  final _events = StreamController<PdfDocumentEvent>.broadcast();
  List<_Page> _pages;
  @override
  List<_Page> get pages => _pages;
  @override
  set pages(List<PdfPage> value) => _pages = value.cast<_Page>();
  @override
  Stream<PdfDocumentEvent> get events => _events.stream;
}

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber) {
    load = () async => _text(pageNumber);
  }
  int reads = 0;
  late Future<PdfPageText> Function() load;
  @override
  final int pageNumber;
  @override
  bool isLoaded = true;
  @override
  Future<PdfPageRawText?> loadText() async {
    reads++;
    final text = await load();
    return PdfPageRawText(text.fullText, text.charRects);
  }
}

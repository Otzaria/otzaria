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
  Completer<void>? clipboardWrite;

  setUp(() {
    document = _Document(3);
    selection = _Selection()..range = _range(1, 3);
    controller = _Controller(document, selection);
    active = true;
    actions = PdfTextSelectionActions(controller, isActive: () => active);
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
      expect(writes, ['selected text']);
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
    expect(writes, ['selected text']);
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
      }
    }

    test('copy stops after a pending text read when $change changes', () async {
      final text = Completer<String>();
      selection.readText = () => text.future;
      final copy = actions.copy();
      await _flush();
      invalidate();
      text.complete('stale text');
      expect(await copy, PdfTextActionResult.none);
      expect(writes, isEmpty);
      expect(selection.clears, 0);
    });

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
      selection.readText = () => Future.error(StateError('closed PDF'));
      expect(await actions.copy(), PdfTextActionResult.failed);
      expect(writes, isEmpty);
      expect(selection.clears, 0);
    },
  );
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
  _Document(int count) : pages = List.generate(count, (i) => _Page(i + 1)) {
    addTearDown(_events.close);
  }
  final _events = StreamController<PdfDocumentEvent>.broadcast();
  @override
  final List<_Page> pages;
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

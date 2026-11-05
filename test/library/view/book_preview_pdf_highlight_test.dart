import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';
import '../../test_helpers/pdf_document_dispose.dart';

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HighlightCanvas implements Canvas {
  final rects = <Rect>[];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late PdfBook book;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = await Directory.systemTemp.createTemp('preview-highlights-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    final file = File('${directory.path}/preview.pdf');
    final source = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('alpha beta alpha')))
      ..addPage(pw.Page(build: (_) => pw.Text('alpha filler gamma')));
    await file.writeAsBytes(await source.save());
    book = PdfBook(title: 'תוצאות חיפוש', path: file.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() async {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  testWidgets('PDF preview highlights the result page and replaces stale '
      'query/page settings (issue #4064)', (tester) async {
    await tester.runAsync(pdfrxFlutterInitialize);
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _SettingsBloc();
    addTearDown(settings.close);

    Future<void> pump(
      String query, {
      int page = 1,
      int distance = 0,
      SearchMode mode = SearchMode.exact,
      Map<int, List<String>> alternatives = const {},
      SearchMatchPolicy policy = SearchMatchPolicy.standard,
      bool isSearchResult = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: BookPreviewPanel(
            book: book,
            searchText: query,
            initialPdfPage: page,
            searchDistance: distance,
            searchMode: mode,
            alternativeWords: alternatives,
            matchPolicy: policy,
            initialTextIsSearchResult: isSearchResult,
          ),
        ),
      ),
    );
    Future<bool> pumpUntil(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      return condition();
    }

    PdfViewer viewer() => tester.widget<PdfViewer>(find.byType(PdfViewer));
    List<Rect> highlights(int pageNumber) {
      final controller = viewer().controller!;
      if (!controller.isReady) return [];
      final page = controller.document.pages[pageNumber - 1];
      final canvas = _HighlightCanvas();
      for (final paint in viewer().params.pagePaintCallbacks ?? []) {
        paint(canvas, Rect.fromLTWH(0, 0, page.width, page.height), page);
      }
      return canvas.rects;
    }

    await pump('alpha');
    expect(await pumpUntil(() => viewer().controller!.isReady), isTrue);
    final controller = viewer().controller!;
    final document = controller.document;
    var disposed = false;
    try {
      expect(await pumpUntil(() => highlights(1).length == 2), isTrue);
      expect(highlights(2), isEmpty);
      expect(highlights(1).every((rect) => !rect.isEmpty), isTrue);

      await pump('alpha', page: 2);
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(viewer().controller, same(controller));
      expect(highlights(1), isEmpty);
      expect(await pumpUntil(() => controller.pageNumber == 2), isTrue);
      final page = document.pages[1];
      final pageSize = Size(page.width, page.height);
      final pageText = (await tester.runAsync(page.loadStructuredText))!;
      PdfPageTextRange textRange(String text) {
        final start = pageText.fullText.indexOf(text);
        expect(start, greaterThanOrEqualTo(0));
        return PdfPageTextRange(
          pageText: pageText,
          start: start,
          end: start + text.length,
        );
      }

      Rect wordRect(String word) =>
          textRange(word).bounds.toRect(page: page, scaledPageSize: pageSize);

      final alpha = wordRect('alpha');
      final gamma = wordRect('gamma');
      final phraseRange = textRange('alpha filler gamma');
      final phraseRects = [
        for (final part in phraseRange.enumerateFragmentBoundingRects())
          part.bounds.toRect(page: page, scaledPageSize: pageSize),
      ];
      expect(phraseRects, isNotEmpty);
      expect(highlights(2), [alpha]);

      await pump('alpha gamma', page: 2);
      expect(highlights(2), isEmpty);
      await pump('alpha gamma', page: 2, distance: 2);
      expect(
        await pumpUntil(() => highlights(2).length == phraseRects.length),
        isTrue,
      );
      expect(highlights(2), unorderedEquals(phraseRects));
      expect(viewer().controller, same(controller));
      await pump('gamma', page: 2);
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(
        highlights(2),
        [gamma],
        reason: 'Changing the query must clear every previous phrase fragment.',
      );
      await pump('omega', page: 2);
      expect(highlights(2), isEmpty);
      await pump(
        'omega',
        page: 2,
        alternatives: {
          0: ['gamma'],
        },
      );
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(highlights(2), [gamma]);

      await pump('gamma', page: 2, policy: SearchMatchPolicy.smart);
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(highlights(2), [gamma]);
      await pump(
        'gamma',
        page: 2,
        policy: SearchMatchPolicy.smart,
        isSearchResult: false,
      );
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(
        highlights(2),
        [gamma],
        reason: 'Actual phrase matches remain highlighted in semantic results.',
      );
      expect(viewer().controller, same(controller));

      // A result line permits per-word fallback when the full fuzzy phrase is
      // absent. Only the result-line flag changes between these three renders.
      await pump(
        'gamma omega',
        page: 2,
        mode: SearchMode.fuzzy,
        policy: SearchMatchPolicy.smart,
      );
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(highlights(2), [gamma]);
      await pump(
        'gamma omega',
        page: 2,
        mode: SearchMode.fuzzy,
        policy: SearchMatchPolicy.smart,
        isSearchResult: false,
      );
      await tester.pump();
      expect(
        highlights(2),
        isEmpty,
        reason:
            'Unmarked result lines must clear the previous per-word fallback.',
      );
      expect(viewer().controller, same(controller));
      await pump(
        'gamma omega',
        page: 2,
        mode: SearchMode.fuzzy,
        policy: SearchMatchPolicy.smart,
      );
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(highlights(2), [gamma]);
      expect(viewer().controller, same(controller));

      // Replace an in-flight page load before the native isolate replies.
      PdfPageTextCache.forDocument(document).clear();
      await pump('alpha', page: 1);
      await pump('gamma', page: 2);
      expect(await pumpUntil(() => highlights(2).length == 1), isTrue);
      expect(highlights(2), [gamma]);
      expect(highlights(1), isEmpty);
      await pump('');
      expect(highlights(1), isEmpty);
      expect(highlights(2), isEmpty);
      expect(tester.takeException(), isNull);

      await pump('alpha');
      await tester.pumpWidget(const SizedBox.shrink());
      await disposePdfDocument(tester, document);
      disposed = true;
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!disposed) await disposePdfDocument(tester, document);
    }
  }, skip: !engineReady);
}

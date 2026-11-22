import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/book_view_layout_document.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late PdfrxEntryFunctions originalBackend;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<bool>(
      SettingsRepository.keyPdfBookViewByDefault,
      true,
    );
    directory = Directory.systemTemp.createTempSync('otzaria-layout-memo-');
    originalBackend = PdfrxEntryFunctions.instance;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() {
    PdfrxEntryFunctions.instance = originalBackend;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  Future<PdfViewerParams> pumpParams(WidgetTester tester) async {
    final backend = _PendingBackend();
    PdfrxEntryFunctions.instance = backend;
    final file = File('${directory.path}/book.pdf')
      ..writeAsStringSync('pending');
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקת פריסה', path: file.path),
      pageNumber: 1,
    );
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = StubSettingsBloc(
      SettingsState.initial().copyWith(pdfBookViewByDefault: true),
    );
    final tour = TourCubit();
    addTearDown(tabsBloc.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: PdfBookScreen(tab: tab),
        ),
      ),
    );
    for (var i = 0; i < 100 && !backend.opened; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(backend.opened, isTrue);
    final params = tester.widget<PdfViewer>(find.byType(PdfViewer)).params;
    expect(params.layoutPages, isNotNull);
    return params;
  }

  testWidgets('callback האפליקציה אינו סורק עמודים בכל pan/zoom', (
    tester,
  ) async {
    final params = await pumpParams(tester);
    const updates = 100;
    final measurements = <Map<String, int>>[];
    final documents = <CountingLayoutDocument>[];
    try {
      for (final pageCount in [100, 1000, 10000]) {
        final document = CountingLayoutDocument(
          List.filled(pageCount, const Size(400, 600)),
        );
        documents.add(document);
        params.onDocumentChanged!(document);
        final first = params.layoutPages!(document.pages, params);
        final samples = <int>[];
        var reads = 0;
        for (var sample = 0; sample < 7; sample++) {
          document.dimensionReads = 0;
          final clock = Stopwatch()..start();
          PdfPageLayout? latest;
          for (var i = 0; i < updates; i++) {
            latest = params.layoutPages!(document.pages, params);
          }
          clock.stop();
          expect(latest, same(first));
          if (sample >= 2) samples.add(clock.elapsedMicroseconds);
          reads = document.dimensionReads;
        }
        samples.sort();
        measurements.add({
          'pages': pageCount,
          'updates': updates,
          'dimensionReads': reads,
          'medianUs': samples[samples.length ~/ 2],
          'maxUs': samples.last,
        });
      }
      debugPrint('book-layout-callback-only ${jsonEncode(measurements)}');
      for (final measurement in measurements) {
        expect(
          measurement['dimensionReads'],
          0,
          reason: '${measurement['pages']} pages / $updates callbacks',
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      for (final document in documents) {
        await document.dispose();
      }
    }
  });

  testWidgets('callback המסמך מחליף מאזין ומבטל קישור בסגירה וב־dispose', (
    tester,
  ) async {
    final params = await pumpParams(tester);
    final first = CountingLayoutDocument(const [Size(400, 600)]);
    final second = CountingLayoutDocument(const [Size(300, 500)]);
    try {
      params.onDocumentChanged!(first);
      expect(first.hasListener, isTrue);
      expect(
        params.layoutPages!(first.pages, params).pageLayouts.single.size,
        const Size(400, 600),
      );
      params.onDocumentChanged!(second);
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isTrue);
      expect(
        params.layoutPages!(second.pages, params).pageLayouts.single.size,
        const Size(300, 500),
      );
      final page = second.pages.single as CountingLayoutPage;
      page.size = const Size(500, 300);
      second.emit(
        PdfDocumentPageStatusChangedEvent(
          second,
          changes: {1: PdfPageStatusChange.modified(page: page)},
        ),
      );
      expect(
        params.layoutPages!(second.pages, params).pageLayouts.single.size,
        const Size(500, 300),
      );
      params.onDocumentChanged!(null);
      expect(second.hasListener, isFalse);
      params.onDocumentChanged!(second);
      expect(second.hasListener, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isFalse);
      await first.dispose();
      await second.dispose();
    }
  });

  testWidgets('callback מאוחר אינו נקשר למסמך אחרי dispose של המסך', (
    tester,
  ) async {
    final params = await pumpParams(tester);
    final document = CountingLayoutDocument(const [Size(400, 600)]);
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      params.onDocumentChanged!(document);
      await tester.pump();
      expect(document.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await document.dispose();
    }
  });
}

class _PendingBackend implements PdfrxEntryFunctions {
  bool opened = false;
  final _document = Completer<PdfDocument>();

  @override
  Future<void> init() async {}

  @override
  Future<PdfDocument> openFile(
    String path, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) {
    opened = true;
    return _document.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

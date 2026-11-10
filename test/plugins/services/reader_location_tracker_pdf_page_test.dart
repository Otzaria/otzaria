import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/plugins/services/reader_location_tracker.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/pdf_document_dispose.dart';
import '../../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-location-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final withOutline in [true, false]) {
    testWidgets(
      'מעבר עמוד ב-PDF בתוך אותו פרק שולח לתוספים את העמוד החדש '
      '(${withOutline ? 'עם' : 'בלי'} תוכן עניינים)',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final file = File('${directory.path}/book.pdf');
        await tester.runAsync(() async {
          await pdfrxFlutterInitialize();
          final pdf = pw.Document();
          for (var i = 0; i < 10; i++) {
            final text = pw.Text('page ${i + 1}');
            pdf.addPage(
              pw.Page(
                build: (_) => withOutline && i == 0
                    ? pw.Outline(name: 'a', title: 'Chapter A', child: text)
                    : text,
              ),
            );
          }
          await file.writeAsBytes(await pdf.save());
        });
        final tab = PdfBookTab(
          book: PdfBook(title: 'ספר בדיקה', path: file.path),
          pageNumber: 1,
        );
        final tabsBloc = TabsBloc(repository: _TabsRepository());
        // ignore: invalid_use_of_visible_for_testing_member
        tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
        final events = <Map<String, dynamic>>[];
        final tracker = ReaderLocationTracker(
          tabsBloc: tabsBloc,
          dispatchEvent: (topic, payload) async {
            if (topic == 'reader.current_ref_changed') {
              events.add(Map.of(payload));
            }
          },
        );
        final settings = StubSettingsBloc();
        final tour = TourCubit();
        addTearDown(tracker.dispose);
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
        final bloc = tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();
        for (var i = 0; i < 100 && bloc.state is! PdfBookLoaded; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(bloc.state, isA<PdfBookLoaded>());
        final document = tab.pdfViewerController.document;
        await settle(tester, rounds: 30);

        final chapterA = withOutline ? 'Chapter A' : '';
        expect(tab.currentTitle.value, chapterA);
        expect(events.last['currentIndex'], 1);

        // גלילה של המשתמש בתוך הפרק: הכותרת נשארת, רק העמוד מתחלף.
        await tester.timedDrag(
          find.byType(PdfViewer),
          const Offset(0, -2500),
          const Duration(milliseconds: 500),
        );
        await settle(tester);

        expect(tab.pageNumber, greaterThan(1));
        expect(tab.currentTitle.value, chapterA);
        expect(
          events.last,
          containsPair('currentIndex', tab.pageNumber),
          reason: 'התוסף לא קיבל את מעבר העמוד בתוך הפרק',
        );
        expect(
          events.last['currentRef'],
          withOutline ? 'Chapter A' : 'עמוד ${tab.pageNumber}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await disposePdfDocument(tester, document);
      },
    );
  }

  test('PDF בחלונית פעילה של פיצול: מעבר עמוד נשלח לתוספים', () async {
    final pdf = PdfBookTab(
      book: PdfBook(title: 'ספר PDF', path: '${directory.path}/a.pdf'),
      pageNumber: 3,
    )..currentTitle.value = 'פרק א';
    final text = TextBookTab(book: TextBook(title: 'ספר טקסט'), index: 1)
      ..currentTitle.value = 'פרק ב';
    final base = TabsState(
      tabs: [CombinedTab(rightTab: pdf, leftTab: text)],
      currentTabIndex: 0,
      rawActivePane: pdf,
    );
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabsBloc.emit(base);
    final events = <Map<String, dynamic>>[];
    final tracker = ReaderLocationTracker(
      tabsBloc: tabsBloc,
      debounceDuration: Duration.zero,
      dispatchEvent: (_, payload) async => events.add(Map.of(payload)),
    );
    addTearDown(tracker.dispose);
    addTearDown(tabsBloc.close);
    Future<void> settle() => Future.delayed(const Duration(milliseconds: 20));
    await settle();
    expect(events.single['currentIndex'], 3);

    pdf.pageNumber = 4;
    await settle();
    expect(events.last, containsPair('currentIndex', 4));
    expect(events.last['currentRef'], 'פרק א');
  });
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

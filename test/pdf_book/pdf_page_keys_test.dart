// PageDown/PageUp מדפדפים בקורא ה-PDF כמו ←/→ (issue #3272).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart'
    show PdfLayoutMode;
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/pdf_document_dispose.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-page-keys-');
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
    ShortcutHelper.isMacForTesting = null;
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

  Future<(PdfBookBloc, PdfBookTab)> pumpBook(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 12; i++) {
        pdf.addPage(pw.Page(build: (_) => pw.Text('page ${i + 1}')));
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
    final settings = StubSettingsBloc();
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
    final bloc = tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();
    for (var i = 0; i < 100 && bloc.state is! PdfBookLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(bloc.state, isA<PdfBookLoaded>());
    await settle(tester, rounds: 30);
    return (bloc, tab);
  }

  Future<void> dragIntoViewer(WidgetTester tester) async {
    await tester.dragFrom(
      tester.getCenter(find.byType(PdfViewer)),
      const Offset(0, -60),
    );
    await settle(tester, rounds: 5);
    final readerFocus = Focus.of(tester.element(find.byType(PdfViewer)));
    expect(readerFocus.hasFocus, isTrue);
    expect(readerFocus.hasPrimaryFocus, isFalse);
  }

  for (final isMac in [false, true]) {
    testWidgets(
      'חיפוש PDF מכבד פריסה עברית וקיצור מותאם: mac=$isMac (issue #3498)',
      (tester) async {
        ShortcutHelper.isMacForTesting = isMac;
        final (bloc, tab) = await pumpBook(tester);
        final document = tab.pdfViewerController.document;
        final modifier = isMac
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        final physicalModifier = isMac
            ? PhysicalKeyboardKey.metaLeft
            : PhysicalKeyboardKey.controlLeft;
        Future<void> hideSearch() async {
          bloc.add(const ToggleLeftPane(false));
          await settle(tester, rounds: 3);
          await dragIntoViewer(tester);
          expect((bloc.state as PdfBookLoaded).showLeftPane, isFalse);
        }

        Future<void> pressHebrewSearch() async {
          // The raw Android/Windows test key-code tables do not contain Hebrew
          // letters. KeyData also reaches FocusManager, unlike calling
          // HardwareKeyboard.handleKeyEvent directly.
          final received =
              <(PhysicalKeyboardKey, LogicalKeyboardKey, bool, bool)>[];
          KeyEventResult observe(KeyEvent event) {
            if (event is KeyDownEvent &&
                event.physicalKey == PhysicalKeyboardKey.keyF) {
              final keyboard = HardwareKeyboard.instance;
              received.add((
                event.physicalKey,
                event.logicalKey,
                keyboard.isControlPressed,
                keyboard.isMetaPressed,
              ));
            }
            return KeyEventResult.ignored;
          }

          void send(
            ui.KeyEventType type,
            PhysicalKeyboardKey physical,
            LogicalKeyboardKey logical,
          ) {
            // Match PluginHostShortcuts' embedder path. Synthesized events are
            // dispatched immediately without waiting for a raw-key message.
            // ignore: deprecated_member_use
            ServicesBinding.instance.keyEventManager.handleKeyData(
              ui.KeyData(
                timeStamp: Duration(
                  microseconds: DateTime.now().microsecondsSinceEpoch,
                ),
                type: type,
                physical: physical.usbHidUsage,
                logical: logical.keyId,
                character: null,
                synthesized: true,
              ),
            );
          }

          FocusManager.instance.addEarlyKeyEventHandler(observe);
          try {
            send(ui.KeyEventType.down, physicalModifier, modifier);
            send(
              ui.KeyEventType.down,
              PhysicalKeyboardKey.keyF,
              const LogicalKeyboardKey(0x05db),
            );
            send(
              ui.KeyEventType.up,
              PhysicalKeyboardKey.keyF,
              const LogicalKeyboardKey(0x05db),
            );
            send(ui.KeyEventType.up, physicalModifier, modifier);
          } finally {
            FocusManager.instance.removeEarlyKeyEventHandler(observe);
          }
          expect(
            received,
            [
              (
                PhysicalKeyboardKey.keyF,
                const LogicalKeyboardKey(0x05db),
                !isMac,
                isMac,
              ),
            ],
            reason: 'The Hebrew key and its modifier must reach FocusManager.',
          );
          expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
          await settle(tester, rounds: 3);
        }

        try {
          await hideSearch();
          await pressHebrewSearch();
          expect((bloc.state as PdfBookLoaded).showLeftPane, isTrue);
          expect(
            tester
                .widget<TabBarView>(find.byType(TabBarView))
                .controller!
                .index,
            1,
          );
          expect(
            tester
                .widget<EditableText>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is EditableText &&
                        widget.controller == tab.searchController,
                  ),
                )
                .focusNode
                .hasFocus,
            isTrue,
          );

          await Settings.setValue(
            ShortcutValidator.currentWindowSearchKey,
            'f6',
          );
          await hideSearch();
          await pressHebrewSearch();
          expect((bloc.state as PdfBookLoaded).showLeftPane, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.f6);
          await settle(tester, rounds: 3);
          expect((bloc.state as PdfBookLoaded).showLeftPane, isTrue);

          await Settings.setValue(ShortcutValidator.currentWindowSearchKey, '');
          await hideSearch();
          await pressHebrewSearch();
          await tester.sendKeyEvent(LogicalKeyboardKey.f6);
          await settle(tester, rounds: 3);
          expect((bloc.state as PdfBookLoaded).showLeftPane, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await disposePdfDocument(tester, document);
        }
      },
    );
  }

  for (final shifted in [false, true]) {
    final shortcut = shifted ? 'shift+f' : 'f';
    testWidgets('קיצור חיפוש PDF "$shortcut" נשמר להקלדה בשדה', (
      tester,
    ) async {
      ShortcutHelper.isMacForTesting = false;
      await Settings.setValue(
        ShortcutValidator.currentWindowSearchKey,
        shortcut,
      );
      final (bloc, tab) = await pumpBook(tester);
      final document = tab.pdfViewerController.document;

      Future<bool> pressF({bool shift = false, bool control = false}) async {
        if (control) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        }
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final handled = await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyF,
          character: shift ? 'F' : 'f',
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        if (control) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        return handled;
      }

      try {
        bloc.add(const ToggleLeftPane(false));
        await settle(tester, rounds: 3);
        await dragIntoViewer(tester);
        expect((bloc.state as PdfBookLoaded).showLeftPane, isFalse);
        expect(ShortcutHelper.isEditingText, isFalse);
        expect(await pressF(shift: shifted), isTrue);
        await settle(tester, rounds: 3);
        expect((bloc.state as PdfBookLoaded).showLeftPane, isTrue);

        final searchField = find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller == tab.searchController,
        );
        await tester.enterText(searchField, 'ערך ');
        await tester.pump();
        expect(ShortcutHelper.isEditingText, isTrue);
        expect(
          await pressF(shift: shifted),
          isFalse,
          reason:
              'Printable search shortcuts must reach text input while editing.',
        );
        // Widget tests deliver platform text input separately from key events.
        final typed = 'ערך ${shifted ? 'F' : 'f'}';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );
        await tester.pump();
        expect(tab.searchController.text, typed);

        await Settings.setValue(ShortcutValidator.currentWindowSearchKey, 'f6');
        final functionKeyHandled = await tester.sendKeyDownEvent(
          LogicalKeyboardKey.f6,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.f6);
        expect(functionKeyHandled, isTrue);
        await Settings.setValue(
          ShortcutValidator.currentWindowSearchKey,
          'ctrl+f',
        );
        expect(await pressF(control: true), isTrue);
        expect(tab.searchController.text, typed);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await disposePdfDocument(tester, document);
      }
    });
  }

  testWidgets('קדימה ב־PDF מתעדכן מהמתאר ומדלג פעם אחת כשהחץ מוחזק', (
    tester,
  ) async {
    await Settings.setValue(
      ShortcutValidator.fitPdfViewKey,
      'alt+arrowright',
    );
    final (_, tab) = await pumpBook(tester);
    final controller = tab.pdfViewerController;
    final document = controller.document;
    try {
      await dragIntoViewer(tester);
      final zoomBefore = controller.currentZoom;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await settle(tester, rounds: 10);
      expect(controller.currentZoom, isNot(closeTo(zoomBefore, 0.01)));

      await Settings.setValue(ShortcutValidator.fitPdfViewKey, '');
      await Settings.setValue(
        ShortcutValidator.nextPdfLocationKey,
        'alt+arrowright',
      );
      final start = PdfReadingLocation.capture(controller)!;
      final ahead = PdfReadingLocation(
        pageNumber: 6,
        pageOffset: start.pageOffset,
        zoom: start.zoom,
      );
      tab.navigationHistory.remember(start);
      expect(tab.navigationHistory.takePrevious(ahead), start);
      tab.outline.value = null;
      await tester.pump();
      final forward = find.byKey(const ValueKey('pdf-forward-location'));
      String tooltip() => tester.widget<BarButton>(forward).tooltip;
      expect(tooltip(), 'מעבר קדימה אל עמוד 6');

      tab.outline.value = [
        PdfOutlineNode(
          title: 'כותרת חדשה',
          dest: PdfDest(6, PdfDestCommand.fit, null),
          children: const [],
        ),
      ];
      await tester.pump();
      expect(tooltip(), 'מעבר קדימה אל כותרת חדשה');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester, rounds: 5);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await settle(tester, rounds: 15);
      expect(controller.pageNumber, 6);
      expect(tab.navigationHistory.last?.pageNumber, start.pageNumber);
      expect(forward, findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await settle(tester, rounds: 5);
      expect(controller.pageNumber, start.pageNumber);
      expect(tab.navigationHistory.next?.pageNumber, 6);

      final beforeLink = Matrix4.copy(controller.value);
      final direct = controller.goToPage(pageNumber: 8);
      await settle(tester, rounds: 15);
      await direct;
      final directView = controller.visibleRect;
      await controller.goTo(beforeLink, duration: Duration.zero);
      await settle(tester, rounds: 3);
      final previousLocation = PdfReadingLocation.capture(controller);

      final tabs = tester.element(find.byType(PdfViewer)).read<TabsBloc>();
      tabs.add(
        OpenOrFocusTab(
          PdfBookTab(book: tab.book, pageNumber: 8),
          navigateToPositionIfReused: true,
        ),
      );
      await settle(tester, rounds: 15);
      expect(
        (controller.visibleRect.center - directView.center).distance,
        lessThan(0.01),
      );
      expect(tab.navigationHistory.next, isNull);
      expect(tab.navigationHistory.last, previousLocation);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await disposePdfDocument(tester, document);
    }
  });

  for (final bookView in [false, true]) {
    testWidgets(
      'PageDown לעמוד הבא ו-PageUp לקודם, Alt+PageDown אינו מדפדף: '
      'bookView=$bookView (issue #3272)',
      (tester) async {
        final (bloc, tab) = await pumpBook(tester);
        final controller = tab.pdfViewerController;
        final document = controller.document;
        try {
          if (bookView) {
            bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
            await settle(tester, rounds: 30);
          }
          // לחיצה באזור הקריאה, כמו המשתמש.
          await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
          await settle(tester, rounds: 3);
          expect(controller.pageNumber, 1);

          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
          await settle(tester, rounds: 20);
          expect(controller.pageNumber, 2);

          await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
          await settle(tester, rounds: 20);
          expect(controller.pageNumber, 1);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          await settle(tester, rounds: 20);
          expect(controller.pageNumber, 1, reason: 'Alt+PageDown שייך לקיצור');
          // גרירה מעבירה את הפוקוס ל-pdfrx; גם שם מדפדפים כמו בחץ (זוג עמודים).
          await dragIntoViewer(tester);
          for (final modifier in [
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.altLeft,
            LogicalKeyboardKey.metaLeft,
          ]) {
            await tester.sendKeyDownEvent(modifier);
            await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
            await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
            await tester.sendKeyUpEvent(modifier);
            await settle(tester, rounds: 3);
            expect(controller.pageNumber, 1, reason: '$modifier שייך לקיצורים');
          }
          for (var i = 0; i < 2; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
            await settle(tester, rounds: 20);
          }
          expect(controller.pageNumber, bookView ? 4 : 3);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await disposePdfDocument(tester, document);
        }
      },
    );
    testWidgets(
      'החזקת PageDown/PageUp אחרי גרירה ממשיכה לדפדף: bookView=$bookView',
      (tester) async {
        final (bloc, tab) = await pumpBook(tester);
        final controller = tab.pdfViewerController;
        final document = controller.document;
        try {
          if (bookView) {
            bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
            await settle(tester, rounds: 30);
          }
          await dragIntoViewer(tester);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
          await settle(tester, rounds: 20);
          for (var i = 0; i < 3; i++) {
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
            await settle(tester, rounds: 20);
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
          expect(controller.pageNumber, bookView ? 8 : 5);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.pageUp);
          await settle(tester, rounds: 20);
          for (var i = 0; i < 3; i++) {
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageUp);
            await settle(tester, rounds: 20);
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.pageUp);
          expect(controller.pageNumber, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await disposePdfDocument(tester, document);
        }
      },
    );
  }

  testWidgets('שחרור PageDown אחרי גרירה מבטל דפדופים שממתינים בתצוגת ספר', (
    tester,
  ) async {
    final (bloc, tab) = await pumpBook(tester);
    final controller = tab.pdfViewerController;
    final document = controller.document;
    try {
      bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
      await settle(tester, rounds: 30);
      await dragIntoViewer(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
      await settle(tester, rounds: 30);
      expect(controller.pageNumber, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await settle(tester, rounds: 20);
      expect(controller.pageNumber, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await settle(tester, rounds: 30);
      expect(controller.pageNumber, 8, reason: 'לחיצות קצרות נשמרות בתור');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await disposePdfDocument(tester, document);
    }
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

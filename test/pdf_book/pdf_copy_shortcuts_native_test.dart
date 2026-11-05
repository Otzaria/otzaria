import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/pdf_book/utils/pdf_text_selection_actions.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_page_number_display.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/pdf_document_dispose.dart';

/// #3776: מסנן המקלדת של 889193890 העביר כל צירוף Ctrl לאפליקציה, ו-Ctrl+C
/// ו-Ctrl+A הפסיקו להגיע לבחירה שב-PDF.
void main() {
  testWidgets('PDF אמיתי: Ctrl+A בוחר, Ctrl+C מעתיק עם חיווי, '
      'וקיצורי Alt/Ctrl של הקורא ממשיכים לעבוד', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await Settings.init(cacheProvider: MemorySettingsCache());
    final directory = Directory.systemTemp.createTempSync('otzaria-pdf-copy-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));
    final clipboard = <String>[];
    Completer<void>? clipboardWrite;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
        await clipboardWrite?.future;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final originalModulePath = Pdfrx.pdfiumModulePath;
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/${Platform.isWindows
          ? 'pdfium.dll'
          : Platform.isMacOS
          ? 'libpdfium.dylib'
          : 'libpdfium.so'}',
    ).absolute.path;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModulePath);
    final path = '${directory.path}/book.pdf';
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 4; i++) {
        pdf.addPage(
          pw.Page(build: (_) => pw.Center(child: pw.Text('Page text $i'))),
        );
      }
      File(path).writeAsBytesSync(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: path),
      pageNumber: 1,
    );
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = _SettingsBloc();
    final tour = TourCubit();
    addTearDown(tabsBloc.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: Scaffold(body: PdfBookScreen(tab: tab)),
        ),
      ),
    );
    final viewer = find.byType(PdfViewer);
    final bloc = tester.element(viewer).read<PdfBookBloc>();
    Future<void> settle([int frames = 15]) async {
      for (var i = 0; i < frames; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> chord(
      List<LogicalKeyboardKey> modifiers,
      LogicalKeyboardKey key,
    ) async {
      for (final modifier in modifiers) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyEvent(key);
      for (final modifier in modifiers.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await settle();
    }

    for (var i = 0; i < 200 && bloc.state is! PdfBookLoaded; i++) {
      await settle(1);
    }
    expect(bloc.state, isA<PdfBookLoaded>());
    final controller = tab.pdfViewerController;
    final document = controller.document;
    final selection = controller.textSelectionDelegate;
    final command = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.tapAt(tester.getCenter(viewer));
    await settle();

    // Ctrl+C בלי בחירה אינו דורס את הלוח.
    await chord([command], LogicalKeyboardKey.keyC);
    expect(clipboard, isEmpty);

    // Ctrl+Shift+A שייך לאפליקציה ואינו בוחר.
    await chord([
      command,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyA);
    expect(selection.hasSelectedText, isFalse);

    await chord([command], LogicalKeyboardKey.keyA);
    expect(selection.hasSelectedText, isTrue);

    await chord([command], LogicalKeyboardKey.keyC);
    expect(clipboard, hasLength(1));
    expect(clipboard.single, contains('Page text 0'));
    expect(clipboard.single, contains('Page text 3'));
    expect(find.text(CommonMessages.textCopied), findsOneWidget);
    expect(selection.hasSelectedText, isTrue);
    UiSnack.hide();
    await settle();

    // גרירת בחירה בעכבר מעבירה את הפוקוס לתוך pdfrx; משם Ctrl+C עובר דרך
    // onKey, שמחזיר false לכל צירוף Ctrl.
    controller.requestFocus();
    await settle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<PdfViewer>(),
      isNotNull,
    );
    await chord([command], LogicalKeyboardKey.keyC);
    expect(clipboard, hasLength(2));
    expect(find.text(CommonMessages.textCopied), findsOneWidget);
    UiSnack.hide();
    await settle();

    // "העתקה" בתפריט ההקשר: אותו חיווי, והבחירה מתנקה כמו ב-pdfrx.
    final menu = tester.widget<AppContextMenuRegion>(
      find.descendant(of: viewer, matching: find.byType(AppContextMenuRegion)),
    );
    clipboardWrite = Completer<void>();
    menu
        .menuBuilder(tester.element(viewer), tester.getCenter(viewer))
        .firstWhere((entry) => entry.iconRowActions != null)
        .iconRowActions!
        .firstWhere((action) => action.label == 'העתקה')
        .onTap!();
    await settle();
    expect(clipboard, hasLength(3));
    expect(find.text(CommonMessages.textCopied), findsNothing);
    expect(selection.hasSelectedText, isTrue);
    clipboardWrite.complete();
    clipboardWrite = null;
    await settle();
    expect(find.text(CommonMessages.textCopied), findsOneWidget);
    expect(selection.hasSelectedText, isFalse);
    UiSnack.hide();
    await settle();

    for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyA]) {
      await Settings.setValue<String>(
        ShortcutValidator.currentWindowSearchKey,
        key == LogicalKeyboardKey.keyC ? 'ctrl+c' : 'ctrl+a',
      );
      await tester.tapAt(tester.getCenter(viewer));
      // pdfrx מחכה להכרעת לחיצה כפולה לפני שהלחיצה הבודדת מבקשת פוקוס.
      await settle();
      expect(
        Focus.of(tester.element(viewer), createDependency: false).hasFocus,
        isTrue,
        reason: 'PDF focus before ${key.debugName}',
      );
      await chord([command], key);
      expect(ShortcutHelper.isEditingText, isTrue, reason: key.debugName);
      expect(clipboard, hasLength(3));
      expect(selection.hasSelectedText, isFalse);
    }
    await Settings.setValue<String>(
      ShortcutValidator.currentWindowSearchKey,
      'ctrl+f',
    );

    // קיצורי הקורא ש-889193890 הגן עליהם: Alt+Left ו-Ctrl+Shift+0.
    unawaited(controller.goToPage(pageNumber: 2, duration: Duration.zero));
    await settle();
    final saved = PdfReadingLocation.capture(controller)!;
    final pageNumber = tester.widget<PageNumberDisplay>(
      find.byType(PageNumberDisplay),
    );
    unawaited(pageNumber.onNavigateToPage!(4));
    await settle();
    expect(controller.pageNumber, 4);
    await tester.tapAt(tester.getCenter(viewer));
    await chord([LogicalKeyboardKey.altLeft], LogicalKeyboardKey.arrowLeft);
    expect(controller.pageNumber, saved.pageNumber);
    expect(tab.navigationHistory.canGoBack, isFalse);

    await chord([
      command,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.digit0);
    final widthZoom = controller.currentZoom;
    await chord([
      command,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.digit0);
    expect(controller.currentZoom, lessThan(widthZoom));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
    await disposePdfDocument(tester, document);
  });

  testWidgets('progressive PDF: select-all preserves an existing selection '
      'until a complete retry', (tester) async {
    final originalModulePath = Pdfrx.pdfiumModulePath;
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/${Platform.isWindows
          ? 'pdfium.dll'
          : Platform.isMacOS
          ? 'libpdfium.dylib'
          : 'libpdfium.so'}',
    ).absolute.path;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModulePath);
    final document = (await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 30; i++) {
        pdf.addPage(
          pw.Page(build: (_) => pw.Center(child: pw.Text('Page text $i'))),
        );
      }
      return PdfDocument.openData(
        await pdf.save(),
        useProgressiveLoading: true,
      );
    }))!;
    final controller = PdfViewerController();
    var ready = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 400,
            child: PdfViewer(
              PdfDocumentRefDirect(document, autoDispose: false),
              controller: controller,
              params: PdfViewerParams(
                onViewerReady: (_, _) => ready = true,
                textSelectionParams: PdfTextSelectionParams(
                  showContextMenuAutomatically: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    try {
      for (var i = 0; i < 40 && !ready; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(ready, isTrue);
      final first = (await tester.runAsync(
        document.pages.first.loadStructuredText,
      ))!;
      final selection = controller.textSelectionDelegate;
      final oldRange = PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(first, 0),
        PdfTextSelectionPoint(first, first.charRects.length - 1),
      );
      await selection.setTextSelectionPointRange(oldRange);
      expect(document.pages.any((page) => !page.isLoaded), isTrue);
      final actions = PdfTextSelectionActions(controller, isActive: () => true);
      expect(await actions.selectAll(), PdfTextActionResult.loading);
      expect(selection.textSelectionPointRange!.start, oldRange.start);
      expect(selection.textSelectionPointRange!.end, oldRange.end);

      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 100 && document.pages.any((p) => !p.isLoaded); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(document.pages.every((page) => page.isLoaded), isTrue);
      expect(
        await tester.runAsync(actions.selectAll),
        PdfTextActionResult.none,
      );
      expect(selection.textSelectionPointRange!.start.text.pageNumber, 1);
      expect(selection.textSelectionPointRange!.end.text.pageNumber, 30);
      final text = await tester.runAsync(selection.getSelectedText);
      expect(text, contains('Page text 0'));
      expect(text, contains('Page text 29'));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
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

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/input_dialog.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/printing_raster_idle.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _SettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

class _ProtectedBookRepository extends Fake implements SeforimRepository {
  @override
  Future<BookProtectionTables> getBookProtectionTables() async => (
    levels: <int, int>{1: 2},
    banners: <int, String>{},
    booksByTitle: <String, List<({int id, int? categoryId})>>{
      'stream-output': [(id: 1, categoryId: null)],
    },
  );
}

class _RecordingPrinter extends PrintingPlatform {
  int requests = 0;
  Future<void> Function(LayoutCallback, PdfPageFormat)? runLayout;

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    requests++;
    await runLayout?.call(onLayout, format);
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    requests++;
    throw UnsupportedError(
      'Unexpected printing call: ${invocation.memberName}',
    );
  }
}

class _FolderPicker extends FilePickerPlatform with MockPlatformInterfaceMixin {
  _FolderPicker(this.select);
  Future<String?> Function() select;
  int selections = 0;
  int byteSaves = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    selections++;
    return select();
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    byteSaves++;
    throw StateError('Desktop PDF export must not use the byte save API.');
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'The PDF export did not settle.');
}

Future<T> _settle<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  future.then<void>(
    (_) => done = true,
    onError: (Object _, StackTrace _) => done = true,
  );
  await _waitFor(tester, () => done);
  return future;
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const filePicker = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final originalModule = Pdfrx.pdfiumModulePath;
  late FilePickerPlatform originalPicker;
  int? originalOwner;
  late Directory directory;
  late Directory output;
  late File input;
  late Uint8List inputBytes;
  late _FolderPicker picker;
  late bool closed;
  bool? saved;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    final document = pw.Document();
    for (var page = 1; page <= 5; page++) {
      document.addPage(pw.Page(build: (_) => pw.Text('page $page')));
    }
    inputBytes = await document.save();
  });

  setUp(() async {
    await Settings.setValue<int>('key-print-destination', 0);
    directory = Directory.systemTemp.createTempSync('otzaria-file-export-');
    output = Directory('${directory.path}/output')..createSync();
    input = File('${directory.path}/input.pdf')..writeAsBytesSync(inputBytes);
    picker = _FolderPicker(() async => output.path);
    originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    originalOwner = DialogOwner.hwnd();
    DialogOwner.mainWindowHwnd = 101;
    closed = false;
    saved = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => directory.path);
    if (Platform.isMacOS) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePicker, (call) async {
            if (call.method == 'dir') return picker.getDirectoryPath();
            throw StateError('Unexpected byte picker: ${call.method}');
          });
    }
  });

  tearDown(() {
    PrintingScreen.debugOnPrintBlocks = null;
    FilePickerPlatform.instance = originalPicker;
    DialogOwner.mainWindowHwnd = originalOwner;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    if (Platform.isMacOS) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePicker, null);
    }
    directory.deleteSync(recursive: true);
  });

  tearDownAll(() => Pdfrx.pdfiumModulePath = originalModule);

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await drainPrintingRasterQueue(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void Function(String)> open(
    WidgetTester tester, {
    Future<Uint8List> Function()? create,
    int? initialPage,
    bool isBookView = false,
    bool text = false,
    TextBook? book,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => dispose(tester));
    await tester.runAsync(pdfrxFlutterInitialize);
    final settings = _MockSettingsBloc();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    final data = Future.value('ספר בדיקה\nשלום עולם\nשורה נוספת');
    final Future<Uint8List> Function(PdfPageFormat)? createOverride =
        create == null ? null : (_) => create();
    var path = input.path;
    late StateSetter replace;
    await tester.pumpWidget(
      RepositoryProvider<SettingsRepository>.value(
        value: _SettingsRepository(),
        child: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('open'),
                  onPressed: () async {
                    saved = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => StatefulBuilder(
                        builder: (context, setState) {
                          replace = setState;
                          return PrintingScreen(
                            data: data,
                            bookId: 'stream-output',
                            book: book,
                            pdfFilePath: create != null || text ? null : path,
                            createPdfOverride: createOverride,
                            initialPage: initialPage,
                            isBookView: isBookView,
                            startLine: 1,
                            endLine: 3,
                          );
                        },
                      ),
                    );
                    closed = true;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (replacement) => replace(() => path = replacement);
  }

  bool settingsBlocked(WidgetTester tester) => tester
      .widgetList<IgnorePointer>(
        find.ancestor(
          of: find.byType(PrintingPagesPerSheetDropdownRow),
          matching: find.byType(IgnorePointer),
        ),
      )
      .any((widget) => widget.ignoring);

  Future<void> chooseName(WidgetTester tester) async {
    await _waitFor(
      tester,
      () => find.byType(InputDialog).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'stream-output.pdf',
    );
    await tester.tap(find.text('שמור'));
    await tester.pump();
  }

  testWidgets('late protection never turns Save into a print request', (
    tester,
  ) async {
    final pending = Completer<SeforimRepository?>();
    BookProtectionRepository.instance.debugRepositoryFor = (_) =>
        pending.future;
    final previousPrinter = PrintingPlatform.instance;
    final printer = _RecordingPrinter();
    PrintingPlatform.instance = printer;
    addTearDown(() {
      BookProtectionRepository.instance.debugReset();
      PrintingPlatform.instance = previousPrinter;
    });
    try {
      await open(tester, book: TextBook(title: 'stream-output'));
      await tester.tap(find.text('שמירה'));
      await tester.pump();
      expect(find.text('שמירה'), findsOneWidget);

      pending.complete(_ProtectedBookRepository());
      await _waitFor(
        tester,
        () => find.text('הדפסה').evaluate().isNotEmpty,
      );
      expect(find.text('הדפסה'), findsWidgets);
      expect(printer.requests, 0);
      expect(picker.selections, 0);
      expect(picker.byteSaves, 0);
      expect(closed, isFalse);
      await dispose(tester);
    } finally {
      if (!pending.isCompleted) pending.complete(null);
    }
  });

  testWidgets('one-up printer read failure is not reported as N-up failure', (
    tester,
  ) async {
    final logging = debugPrint;
    final previousPrinter = PrintingPlatform.instance;
    final messages = <String>[];
    Object? layoutError;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    PrintingPlatform.instance = _RecordingPrinter()
      ..runLayout = (layout, format) async {
        try {
          await layout(format);
        } catch (error) {
          layoutError = error;
          rethrow;
        }
      };
    try {
      await Settings.setValue<int>('key-print-destination', 2);
      input.deleteSync();
      await open(tester);

      await tester.tap(find.widgetWithText(ActionButton, 'הדפסה'));
      await _waitFor(tester, () => layoutError != null);
      expect(layoutError, isA<FileSystemException>());
      expect(messages, isNot(contains(startsWith('[PRINT] N-up failed:'))));
      await dispose(tester);
    } finally {
      debugPrint = logging;
      PrintingPlatform.instance = previousPrinter;
    }
  });

  testWidgets('an unchanged file is copied without the byte save API', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('שמירה'));
    await chooseName(tester);
    await _waitFor(tester, () => closed);
    expect(saved, isTrue);
    expect(picker.selections, 1);
    expect(picker.byteSaves, 0);
    expect(output.listSync(), hasLength(1));
    expect(
      File('${output.path}/stream-output.pdf').readAsBytesSync(),
      inputBytes,
    );
    expect(input.readAsBytesSync(), inputBytes);
    await dispose(tester);
  });

  for (final pagesPerSheet in [1, 2, 4]) {
    testWidgets('file export preserves range 2–3 with $pagesPerSheet-up', (
      tester,
    ) async {
      await open(tester, initialPage: 2, isBookView: true);
      tester
          .widget<PrintingPagesPerSheetDropdownRow>(
            find.byType(PrintingPagesPerSheetDropdownRow),
          )
          .onChanged(pagesPerSheet);
      await tester.pump();
      await tester.tap(find.text('שמירה'));
      await chooseName(tester);
      await _waitFor(tester, () => closed);
      expect(saved, isTrue);
      await dispose(tester);
      final document = await _settle(
        tester,
        PdfDocument.openFile('${output.path}/stream-output.pdf'),
      );
      try {
        expect(document.pages, hasLength(pagesPerSheet == 1 ? 2 : 1));
        final extracted = <String>[];
        for (final page in document.pages) {
          extracted.add((await _settle(tester, page.loadText()))!.fullText);
        }
        expect(extracted.join(' '), contains('page 2'));
        expect(extracted.join(' '), contains('page 3'));
        expect(extracted.join(' '), isNot(contains('page 1')));
        expect(extracted.join(' '), isNot(contains('page 4')));
      } finally {
        await _settle(tester, document.dispose());
      }
      expect(picker.byteSaves, 0);
      expect(output.listSync(), hasLength(1));
    });
  }

  testWidgets('text preview and Save reuse one generated file with Hebrew', (
    tester,
  ) async {
    var generated = 0;
    PrintingScreen.debugOnPrintBlocks = (_) => generated++;
    await open(tester, text: true);
    await _waitFor(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
    expect(generated, 1);
    await tester.tap(find.text('שמירה'));
    await chooseName(tester);
    await _waitFor(tester, () => closed);
    expect(saved, isTrue);
    expect(generated, 1, reason: 'Saving must reuse the preview base file.');
    await dispose(tester);
    final document = await _settle(
      tester,
      PdfDocument.openFile('${output.path}/stream-output.pdf'),
    );
    try {
      expect(
        (await _settle(tester, document.pages.first.loadText()))!.fullText,
        contains('שלום עולם'),
      );
    } finally {
      await _settle(tester, document.dispose());
    }
    expect(picker.byteSaves, 0);
  });

  testWidgets('a generation failure leaves the old target and allows retry', (
    tester,
  ) async {
    final target = File('${output.path}/stream-output.pdf')
      ..writeAsStringSync('original');
    final pending = Completer<Uint8List>();
    var calls = 0;
    await open(
      tester,
      create: () {
        calls++;
        return switch (calls) {
          1 => Future.error(StateError('Synthetic preview failure')),
          2 => pending.future,
          _ => Future.value(inputBytes),
        };
      },
    );
    try {
      // Let the initial preview finish failing. The second generation then
      // belongs to Save, independently of native permission setup timing.
      await _waitFor(
        tester,
        () => find
            .byIcon(FluentIcons.error_circle_24_regular)
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.text('שמירה'));
      await chooseName(tester);
      await _waitFor(tester, () => find.text('החלפה').evaluate().isNotEmpty);
      await tester.tap(find.text('החלפה'));
      await _waitFor(tester, () => calls == 2);
      expect(target.readAsStringSync(), 'original');
      expect(output.listSync(), hasLength(2));
      pending.completeError(StateError('Synthetic PDF generation failure'));
      await _waitFor(tester, () => !settingsBlocked(tester));
      expect(target.readAsStringSync(), 'original');
      expect(output.listSync(), hasLength(1));
      expect(closed, isFalse);
      await tester.tap(find.text('שמירה'));
      await chooseName(tester);
      await _waitFor(tester, () => find.text('החלפה').evaluate().isNotEmpty);
      await tester.tap(find.text('החלפה'));
      await _waitFor(tester, () => closed);
      expect(saved, isTrue);
      expect(calls, 3);
      expect(target.readAsBytesSync(), inputBytes);
      expect(output.listSync(), hasLength(1));
      expect(picker.byteSaves, 0);
    } finally {
      if (!pending.isCompleted) pending.complete(inputBytes);
      await dispose(tester);
    }
  });

  testWidgets('cancelling with a pending preview preserves the target', (
    tester,
  ) async {
    final target = File('${output.path}/stream-output.pdf')
      ..writeAsStringSync('original');
    final pending = Completer<Uint8List>();
    var calls = 0;
    await open(
      tester,
      create: () {
        calls++;
        return pending.future;
      },
    );
    try {
      await tester.tap(find.text('שמירה'));
      await chooseName(tester);
      await _waitFor(tester, () => find.text('החלפה').evaluate().isNotEmpty);
      expect(target.readAsStringSync(), 'original');
      await tester.tap(find.text('החלפה'));
      await _waitFor(tester, () => output.listSync().length == 2);
      expect(calls, 1);
      await tester.tap(find.text('ביטול'));
      pending.complete(inputBytes);
      await _waitFor(tester, () => closed && output.listSync().length == 1);
      expect(saved, isNull);
      expect(target.readAsStringSync(), 'original');
      expect(picker.byteSaves, 0);
    } finally {
      if (!pending.isCompleted) pending.complete(inputBytes);
      await dispose(tester);
    }
  });

  testWidgets('a second Save is ignored while target selection is pending', (
    tester,
  ) async {
    final folder = Completer<String?>();
    picker.select = () => folder.future;
    await open(tester);
    try {
      await tester.tap(find.text('שמירה'));
      await tester.tap(find.text('שמירה'));
      // Both taps deliberately happen before a frame, then render the busy UI.
      await tester.pump();
      await _waitFor(tester, () => picker.selections == 1);
      expect(find.text('שמירה'), findsOneWidget);
      expect(settingsBlocked(tester), isTrue);
      folder.complete(null);
      await _waitFor(tester, () => !settingsBlocked(tester));
      expect(picker.selections, 1);
      expect(picker.byteSaves, 0);
      expect(output.listSync(), isEmpty);
    } finally {
      if (!folder.isCompleted) folder.complete(null);
      await dispose(tester);
    }
  });

  testWidgets('source A–B–A while choosing a target cancels the old Save', (
    tester,
  ) async {
    final folder = Completer<String?>();
    picker.select = () => folder.future;
    final replacement = File('${directory.path}/other.pdf')
      ..writeAsBytesSync(inputBytes);
    final replace = await open(tester);
    try {
      await tester.tap(find.text('שמירה'));
      await _waitFor(tester, () => picker.selections == 1);
      replace(replacement.path);
      await tester.pump();
      replace(input.path);
      await tester.pump();
      folder.complete(output.path);
      await _waitFor(tester, () => !settingsBlocked(tester));
      expect(find.byType(InputDialog), findsNothing);
      expect(output.listSync(), isEmpty);
      expect(closed, isFalse);
      expect(picker.byteSaves, 0);
    } finally {
      if (!folder.isCompleted) folder.complete(null);
      await dispose(tester);
    }
  });

  testWidgets('closing the owner while the folder picker waits cancels Save', (
    tester,
  ) async {
    final folder = Completer<String?>();
    picker.select = () => folder.future;
    await open(tester);
    try {
      await tester.tap(find.text('שמירה'));
      await _waitFor(tester, () => picker.selections == 1);
      await tester.tap(find.text('ביטול'));
      await _waitFor(tester, () => closed);
      // The route is still mounted during its closing animation.
      folder.complete(output.path);
      await _settle(tester, folder.future);
      await tester.pump();
      expect(find.byType(InputDialog), findsNothing);
      expect(output.listSync(), isEmpty);
      expect(picker.byteSaves, 0);
    } finally {
      if (!folder.isCompleted) folder.complete(null);
      await dispose(tester);
    }
  });
}

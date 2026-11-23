import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/file/mobile_pdf_export_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/printing_raster_idle.dart';
import '../support/golden_fonts.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _SettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

class _Backend implements MobilePdfExportBackend {
  final requests = <MobilePdfExportRequest>[];
  final cancellations = <String>[];
  final pending = <Completer<MobilePdfExportResult>>[];
  bool acceptCancellation = true;

  @override
  Future<MobilePdfExportResult> exportFile(MobilePdfExportRequest request) {
    requests.add(request);
    final result = Completer<MobilePdfExportResult>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<bool> cancelExport(String operationId) async {
    cancellations.add(operationId);
    return acceptCancellation;
  }

  void complete(
    int index,
    MobilePdfExportStatus status, {
    String? displayName,
    String? residualDocument,
    String? residualDisplayName,
    String? cleanupError,
  }) {
    pending[index].complete(
      MobilePdfExportResult(
        operationId: requests[index].operationId,
        status: status,
        documentUri: status == MobilePdfExportStatus.saved
            ? 'content://otzaria-test/export/${requests[index].operationId}'
            : null,
        displayName: displayName,
        errorCode: status == MobilePdfExportStatus.failed
            ? 'copy_failed'
            : null,
        errorMessage: status == MobilePdfExportStatus.failed
            ? 'private provider diagnostics'
            : null,
        residualDocument: residualDocument,
        residualDisplayName: residualDisplayName,
        cleanupStatus: residualDocument == null
            ? MobilePdfExportCleanupStatus.notNeeded
            : MobilePdfExportCleanupStatus.failed,
        cleanupError: cleanupError,
      ),
    );
  }

  void finishPending() {
    for (var index = 0; index < pending.length; index++) {
      if (!pending[index].isCompleted) {
        complete(index, MobilePdfExportStatus.cancelled);
      }
    }
  }
}

class _ForbiddenBytePicker extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  int byteSaves = 0;
  int directoryPicks = 0;
  Future<Uri?> Function(String, Uint8List)? saveWord;

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
    final save = saveWord;
    if (save != null) return save(fileName, bytes);
    byteSaves++;
    throw StateError('A mobile PDF export must not fall back to Save(bytes).');
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    directoryPicks++;
    throw StateError('A mobile PDF export must not use the desktop chooser.');
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'The mobile PDF export did not settle.');
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

ThemeData _theme(Color seed, Brightness brightness) {
  final theme = AppThemeData.light(
    AppThemeData.createColorScheme(seed, brightness),
    compactMenuMode: false,
    variant: AppThemeVariant.ofSeed(seed),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: goldenUiFontFamily),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: goldenUiFontFamily,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final originalModule = Pdfrx.pdfiumModulePath;
  late FilePickerPlatform originalPicker;
  late _ForbiddenBytePicker picker;
  late _Backend backend;
  late Directory directory;
  late File input;
  late Uint8List inputBytes;
  late AppWindowKeys window;
  late bool closed;
  bool? saved;
  final boundaryKey = GlobalKey();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await loadGoldenFonts();
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
    directory = Directory.systemTemp.createTempSync('otzaria-mobile-ui-');
    input = File('${directory.path}/input.pdf')..writeAsBytesSync(inputBytes);
    backend = _Backend();
    picker = _ForbiddenBytePicker();
    originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    AppWindowKeys.resetForTest();
    window = AppWindowKeys.current;
    closed = false;
    saved = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => directory.path);
  });

  tearDown(() {
    UiSnack.hide(window: window);
    PrintingScreen.debugOnPrintBlocks = null;
    FilePickerPlatform.instance = originalPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    expect(picker.byteSaves, 0);
    expect(picker.directoryPicks, 0);
    directory.deleteSync(recursive: true);
  });

  tearDownAll(() => Pdfrx.pdfiumModulePath = originalModule);

  Future<void> dispose(WidgetTester tester) async {
    UiSnack.hide(window: window);
    await tester.pumpWidget(const SizedBox());
    backend.finishPending();
    await drainPrintingRasterQueue(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void Function(String)> open(
    WidgetTester tester, {
    MobilePdfExportPlatform platform = MobilePdfExportPlatform.android,
    int? initialPage,
    bool isBookView = false,
    bool text = false,
    double width = 1200,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
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
    final service = MobilePdfExportService.withBackend(
      platform: platform,
      backend: backend,
      temporaryDirectory: () async => directory,
    );
    final data = Future.value('ספר בדיקה\nשלום עולם\nשורה נוספת');
    var path = input.path;
    late StateSetter replace;
    await tester.pumpWidget(
      RepositoryProvider<SettingsRepository>.value(
        value: _SettingsRepository(),
        child: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: MaterialApp(
            navigatorKey: window.navigator,
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme:
                theme ?? _theme(AppSeedColors.defaultLight, Brightness.light),
            builder: (context, child) => RepaintBoundary(
              key: boundaryKey,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    saved = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => StatefulBuilder(
                        builder: (context, setState) {
                          replace = setState;
                          return PrintingScreen(
                            data: data,
                            bookId: 'mobile-output',
                            pdfFilePath: text ? null : path,
                            mobileExportService: service,
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
                  child: const Text('open'),
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

  Future<MobilePdfExportRequest> start(WidgetTester tester) async {
    final expected = backend.requests.length + 1;
    await tester.tap(find.text('שמירה'));
    await _waitFor(tester, () => backend.requests.length == expected);
    return backend.requests.last;
  }

  testWidgets(
    'file export uses dedicated staging and reports the provider name',
    (
      tester,
    ) async {
      await open(tester);
      final request = await start(tester);
      final staging = File(request.sourcePath);
      expect(request.fileName, 'mobile-output.pdf');
      expect(staging.absolute.path, isNot(input.absolute.path));
      expect(staging.readAsBytesSync(), inputBytes);
      expect(input.readAsBytesSync(), inputBytes);
      expect(closed, isFalse);
      backend.complete(
        0,
        MobilePdfExportStatus.saved,
        displayName: 'עותק חדש.pdf',
      );
      await _waitFor(tester, () => closed);
      expect(saved, isTrue);
      expect(staging.existsSync(), isFalse);
      expect(
        find.text(PdfMessages.pdfFileSavedAs('עותק חדש.pdf')),
        findsOneWidget,
      );
      await dispose(tester);
    },
  );

  for (final pagesPerSheet in [1, 2, 4]) {
    testWidgets('mobile file preserves range 2–3 with $pagesPerSheet-up', (
      tester,
    ) async {
      await open(tester, initialPage: 2, isBookView: true);
      tester
          .widget<PrintingPagesPerSheetDropdownRow>(
            find.byType(PrintingPagesPerSheetDropdownRow),
          )
          .onChanged(pagesPerSheet);
      await tester.pump();
      final request = await start(tester);
      final exported = File(request.sourcePath).copySync(
        '${directory.path}/exported.pdf',
      );
      backend.complete(0, MobilePdfExportStatus.saved);
      await _waitFor(tester, () => closed);
      await dispose(tester);
      final document = await _settle(
        tester,
        PdfDocument.openFile(exported.path),
      );
      try {
        expect(document.pages, hasLength(pagesPerSheet == 1 ? 2 : 1));
        final text = <String>[];
        for (final page in document.pages) {
          text.add((await _settle(tester, page.loadText()))!.fullText);
        }
        expect(text.join(' '), contains('page 2'));
        expect(text.join(' '), contains('page 3'));
        expect(text.join(' '), isNot(contains('page 1')));
        expect(text.join(' '), isNot(contains('page 4')));
      } finally {
        await _settle(tester, document.dispose());
      }
    });
  }

  testWidgets('Hebrew preview and mobile export share one generated base', (
    tester,
  ) async {
    var generated = 0;
    PrintingScreen.debugOnPrintBlocks = (_) => generated++;
    await open(tester, text: true);
    await _waitFor(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
    expect(generated, 1);
    final request = await start(tester);
    expect(generated, 1);
    final exported = File(request.sourcePath).copySync(
      '${directory.path}/hebrew.pdf',
    );
    backend.complete(0, MobilePdfExportStatus.saved);
    await _waitFor(tester, () => closed);
    await dispose(tester);
    final document = await _settle(tester, PdfDocument.openFile(exported.path));
    try {
      expect(
        (await _settle(tester, document.pages.first.loadText()))!.fullText,
        contains('שלום עולם'),
      );
    } finally {
      await _settle(tester, document.dispose());
    }
  });

  testWidgets(
    'closing the route does not release staging on cancellation ACK',
    (
      tester,
    ) async {
      await open(tester);
      final request = await start(tester);
      await tester.tap(find.text('ביטול'));
      await tester.pump();
      await _waitFor(tester, () => backend.cancellations.isNotEmpty);
      expect(backend.cancellations, [request.operationId]);
      expect(File(request.sourcePath).existsSync(), isTrue);
      await _waitFor(tester, () => closed);
      expect(File(request.sourcePath).existsSync(), isTrue);
      backend.complete(0, MobilePdfExportStatus.cancelled);
      await _waitFor(tester, () => !File(request.sourcePath).existsSync());
      expect(saved, isNull);
      expect(find.text(PdfMessages.pdfFileSaved), findsNothing);
      expect(input.readAsBytesSync(), inputBytes);
    },
  );

  testWidgets('a residual provider document is reported after route disposal', (
    tester,
  ) async {
    await open(tester);
    final request = await start(tester);
    await tester.tap(find.text('ביטול'));
    await _waitFor(tester, () => closed);
    await _waitFor(
      tester,
      () => find.byType(PrintingScreen, skipOffstage: false).evaluate().isEmpty,
    );
    expect(File(request.sourcePath).existsSync(), isTrue);
    backend.complete(
      0,
      MobilePdfExportStatus.cancelled,
      residualDocument: 'content://otzaria-test/export/partial',
      residualDisplayName: 'עותק חלקי.pdf',
      cleanupError: 'provider refused deletion',
    );
    final warning = find.text(
      PdfMessages.mobilePdfExportResidual('עותק חלקי.pdf'),
    );
    await _waitFor(tester, () => warning.evaluate().isNotEmpty);
    expect(warning, findsOneWidget);
    expect(File(request.sourcePath).existsSync(), isFalse);
    expect(find.textContaining('provider refused deletion'), findsNothing);
    expect(saved, isNull);
    await dispose(tester);
  });

  testWidgets('late saved result cannot close a source replaced A–B–A', (
    tester,
  ) async {
    final replace = await open(tester);
    final request = await start(tester);
    backend.acceptCancellation = false;
    final other = input.copySync('${directory.path}/other.pdf');
    replace(other.path);
    await tester.pump();
    replace(input.path);
    await tester.pump();
    await _waitFor(tester, () => backend.cancellations.isNotEmpty);
    expect(backend.cancellations, [request.operationId]);
    expect(File(request.sourcePath).existsSync(), isTrue);
    backend.complete(0, MobilePdfExportStatus.saved);
    await _waitFor(
      tester,
      () => !settingsBlocked(tester),
    );
    expect(closed, isFalse);
    expect(find.text(PdfMessages.pdfFileSaved), findsOneWidget);
    final next = await start(tester);
    expect(next.operationId, isNot(request.operationId));
    backend.complete(1, MobilePdfExportStatus.saved);
    await _waitFor(tester, () => closed);
    expect(saved, isTrue);
    await dispose(tester);
  });

  testWidgets(
    'provider failure has no byte fallback and allows a new attempt',
    (
      tester,
    ) async {
      await open(tester);
      final failed = await start(tester);
      backend.complete(0, MobilePdfExportStatus.failed);
      await _waitFor(
        tester,
        () => !settingsBlocked(tester),
      );
      expect(find.text(PdfMessages.mobilePdfSaveFailed), findsOneWidget);
      expect(find.textContaining('private provider diagnostics'), findsNothing);
      expect(File(failed.sourcePath).existsSync(), isFalse);
      expect(closed, isFalse);
      final retry = await start(tester);
      expect(retry.operationId, isNot(failed.operationId));
      backend.complete(1, MobilePdfExportStatus.saved);
      await _waitFor(tester, () => closed);
      expect(saved, isTrue);
      await dispose(tester);
    },
  );

  testWidgets('two Save taps before a frame start only one native export', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('שמירה'));
    await tester.tap(find.text('שמירה'));
    await tester.pump();
    await _waitFor(tester, () => backend.requests.isNotEmpty);
    expect(backend.requests, hasLength(1));
    expect(find.text('שמירה'), findsOneWidget);
    expect(settingsBlocked(tester), isTrue);
    backend.complete(0, MobilePdfExportStatus.saved);
    await _waitFor(tester, () => closed);
    await dispose(tester);
  });

  testWidgets('iOS uses the file service with the normal Save label', (
    tester,
  ) async {
    await open(tester, platform: MobilePdfExportPlatform.ios);
    expect(find.text('בחירת תיקייה'), findsNothing);
    expect(find.textContaining('הקובץ יישמר כעותק חדש'), findsNothing);
    final request = await start(tester);
    expect(File(request.sourcePath).readAsBytesSync(), inputBytes);
    backend.complete(0, MobilePdfExportStatus.saved);
    await _waitFor(tester, () => closed);
    expect(saved, isTrue);
    await dispose(tester);
  });

  testWidgets(
    'Word retains the byte picker with mobile PDF enabled',
    (
      tester,
    ) async {
      await Settings.setValue<int>('key-print-destination', 1);
      final output = File('${directory.path}/mobile-output.docx');
      final previousOwner = DialogOwner.hwnd();
      DialogOwner.mainWindowHwnd = 101;
      addTearDown(() => DialogOwner.mainWindowHwnd = previousOwner);
      picker.saveWord = (fileName, bytes) async {
        expect(fileName, 'mobile-output.docx');
        await output.writeAsBytes(bytes);
        return output.uri;
      };
      if (Platform.isMacOS) {
        const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'save');
          expect(call.arguments['fileName'], 'mobile-output.docx');
          return output.path;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }

      await open(tester, text: true);
      expect(find.text('שמור ל-Word'), findsOneWidget);
      await tester.tap(find.text('שמירה'));
      await _waitFor(tester, () => closed);
      expect(saved, isTrue);
      expect(backend.requests, isEmpty);
      final document = ZipDecoder().decodeBytes(output.readAsBytesSync());
      expect(document.findFile('word/document.xml'), isNotNull);
      await dispose(tester);
    },
    variant: TargetPlatformVariant.only(
      Platform.isMacOS ? TargetPlatform.macOS : TargetPlatform.android,
    ),
  );

  for (final (name, seed, brightness) in [
    ('light', AppSeedColors.defaultLight, Brightness.light),
    ('dark', AppSeedColors.defaultLight, Brightness.dark),
    ('white', AppSeedColors.white, Brightness.light),
  ]) {
    for (final width in [360.0, 1200.0]) {
      testWidgets(
        'Android PDF controls fit RTL $name at $width and scale 1.3',
        (
          tester,
        ) async {
          List<Rect>? baseline;
          for (final (variant, platform) in [
            ('save', MobilePdfExportPlatform.unsupported),
            ('android', MobilePdfExportPlatform.android),
          ]) {
            await open(
              tester,
              platform: platform,
              width: width,
              textScale: 1.3,
              theme: _theme(seed, brightness),
            );
            await _waitFor(
              tester,
              () => find.byType(RawImage).evaluate().isNotEmpty,
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            final save = find.text('שמירה');
            expect(save, findsOneWidget);
            expect(find.text('בחירת תיקייה'), findsNothing);
            expect(find.textContaining('הקובץ יישמר כעותק חדש'), findsNothing);
            expect(Directionality.of(tester.element(save)), TextDirection.rtl);
            final controls = [
              for (final finder in [
                save,
                find.text('ביטול'),
                find.text('בחר יעד הדפסה'),
                find.text('שמור ל-PDF'),
              ])
                tester.getRect(finder),
            ];
            baseline ??= controls;
            expect(controls, baseline);
            final artifactRoot =
                Platform.environment['OTZARIA_MOBILE_PDF_UI_ARTIFACT_DIR'];
            if (artifactRoot != null) {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await _settle(tester, boundary.toImage());
              try {
                final bytes = await _settle(
                  tester,
                  image.toByteData(format: ui.ImageByteFormat.png),
                );
                final output = Directory(artifactRoot)
                  ..createSync(recursive: true);
                File(
                  '${output.path}/mobile-pdf-$variant-$name-${width.toInt()}.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            }
            await dispose(tester);
          }
        },
      );
    }
  }
}

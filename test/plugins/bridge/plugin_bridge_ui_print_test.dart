import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_print_service.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/file/mobile_pdf_export_service.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:posix/posix.dart' as posix;

import '../../helpers/memory_settings_cache.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _MockPluginRegistryRepository extends Mock
    implements PluginRegistryRepository {}

InstalledPlugin _buildInstalledPlugin() {
  return InstalledPlugin(
    pluginId: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: true,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: 'test.plugin',
      name: 'Test Plugin',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.x',
      permissions: const [],
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: 'שני טורים',
      toolTabOrder: 1,
      defaultPinned: true,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<
    ({
      String pluginId,
      String instanceId,
      String jobName,
      PluginPdfLayout? layout,
    })
  >
  printed;
  late bool printResult;
  late bool userActivated;
  late List<String> savedNames;
  late List<PluginPdfLayout?> capturedLayouts;
  late String? saveLocation;
  late bool overwriteApproved;
  late List<String> overwritePrompts;
  Future<void> Function()? afterOverwritePrompt;
  Completer<void>? captureBarrier;
  Completer<void>? captureStarted;
  Completer<void>? pickerBarrier;
  Completer<void>? pickerStarted;
  late Directory tempDir;
  late PluginBridgeAdapter adapter;

  PluginBridgeAdapter buildAdapter({
    BuildContext? context,
    MobilePdfExportService? mobileService,
  }) {
    return PluginBridgeAdapter(
      _buildInstalledPlugin(),
      instanceId: 'tab-3',
      mobilePdfExportService: mobileService,
      dependencies: PluginBridgeDependencies(
        windowContext: context,
        historyBloc: _MockHistoryBloc(),
        tabsBloc: _MockTabsBloc(),
        navigationBloc: _MockNavigationBloc(),
        calendarCubit: _MockCalendarCubit(),
        workspaceBloc: _MockWorkspaceBloc(),
        searchRepository: _MockSearchRepository(),
        personalNotesRepository: _MockPersonalNotesRepository(),
        bookOpenCoordinator: _MockBookOpenCoordinator(),
        themePayloadBuilder: () => <String, dynamic>{},
        showConfirmDialog: ({required title, required content}) async => true,
        showWarningDialog:
            ({required title, required content, required subtitle}) async {
              overwritePrompts.add(content);
              await afterOverwritePrompt?.call();
              return overwriteApproved;
            },
        printPluginPage:
            (pluginId, instanceId, {required jobName, layout}) async {
              printed.add((
                pluginId: pluginId,
                instanceId: instanceId,
                jobName: jobName,
                layout: layout,
              ));
              return printResult;
            },
        capturePluginPagePdf: (pluginId, instanceId, {layout}) async {
          capturedLayouts.add(layout);
          captureStarted?.complete();
          await captureBarrier?.future;
          return Uint8List.fromList(const [37, 80, 68, 70]);
        },
        hasUserActivation: (pluginId, instanceId) async => userActivated,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async {
              savedNames.add(suggestedName);
              pickerStarted?.complete();
              await pickerBarrier?.future;
              return saveLocation;
            },
      ),
      pluginRepository: _MockPluginRegistryRepository(),
    );
  }

  setUp(() {
    printed = [];
    printResult = true;
    userActivated = true;
    savedNames = [];
    capturedLayouts = [];
    overwriteApproved = true;
    overwritePrompts = [];
    afterOverwritePrompt = null;
    captureBarrier = null;
    captureStarted = null;
    pickerBarrier = null;
    pickerStarted = null;
    tempDir = Directory.systemTemp.createTempSync('otzaria_export_pdf');
    saveLocation = p.join(tempDir.path, 'דף.pdf');
    adapter = buildAdapter();
  });

  tearDown(() {
    adapter.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('ui.print מדפיס את המופע הקורא ומחזיר printed:true', () async {
    final result = await adapter.execute('ui', 'print', {});

    expect(result, {'printed': true});
    expect(printed, hasLength(1));
    expect(printed.single.pluginId, 'test.plugin');
    // ההדפסה חלה על ה-WebView של המופע הקורא, לא על בחירת הדיספצ'ר.
    expect(printed.single.instanceId, 'tab-3');
  });

  test('בלי jobName שם העבודה הוא שם התוסף', () async {
    await adapter.execute('ui', 'print', {});
    expect(printed.single.jobName, 'שני טורים');

    await adapter.execute('ui', 'print', {'jobName': '  '});
    expect(printed.last.jobName, 'שני טורים');
  });

  test('jobName מפורש עובר כמות שהוא', () async {
    await adapter.execute('ui', 'print', {'jobName': 'דף לדוגמה'});
    expect(printed.single.jobName, 'דף לדוגמה');
  });

  test('ביטול בדיאלוג המערכת מוחזר כ-printed:false', () async {
    printResult = false;
    expect(await adapter.execute('ui', 'print', {}), {'printed': false});
  });

  test('ui.exportPdf שומר את הקובץ ומחזיר את שמו בלבד', () async {
    final result =
        await adapter.execute('ui', 'exportPdf', {'fileName': 'שני טורים'})
            as Map<String, dynamic>;

    expect(result['saved'], isTrue);
    expect(result['name'], 'דף.pdf');
    // הנתיב המלא אינו נמסר לתוסף.
    expect(result.containsKey('path'), isFalse);
    expect(savedNames.single, 'שני טורים.pdf');
    expect(File(saveLocation!).readAsBytesSync(), [37, 80, 68, 70]);
  });

  test('ביטול דיאלוג השמירה אינו כותב קובץ', () async {
    saveLocation = null;
    expect(await adapter.execute('ui', 'exportPdf', {}), {
      'saved': false,
      'name': null,
    });
    expect(tempDir.listSync(), isEmpty);
  });

  test('דריסה שאושרה מחליפה רק את הקובץ המלא', () async {
    final target = File(saveLocation!);
    await target.writeAsString('previous document');
    final io = _PdfExportIo(
      afterWrite: (_) async {
        expect(await target.readAsString(), 'previous document');
      },
    );
    final result = await IOOverrides.runWithIOOverrides(
      () => adapter.execute('ui', 'exportPdf', {}),
      io,
    );
    expect(result, {'saved': true, 'name': 'דף.pdf'});
    expect(overwritePrompts, hasLength(1));
    expect(await target.readAsBytes(), [37, 80, 68, 70]);
    expect(tempDir.listSync().map((entry) => entry.path), [target.path]);
  });

  test('דחיית דריסה שומרת את הקובץ ללא staging', () async {
    final target = File(saveLocation!);
    await target.writeAsString('previous document');
    overwriteApproved = false;
    expect(await adapter.execute('ui', 'exportPdf', {}), {
      'saved': false,
      'name': null,
    });
    expect(overwritePrompts, hasLength(1));
    expect(await target.readAsString(), 'previous document');
    expect(tempDir.listSync().map((entry) => entry.path), [target.path]);
  });

  for (final failurePoint in ['write', 'flush', 'rename']) {
    test('כשל $failurePoint משאיר יעד קיים שלם ומנקה staging', () async {
      final target = File(saveLocation!);
      await target.writeAsString('previous document');
      final failure = FileSystemException(
        'injected $failurePoint failure',
        target.path,
      );
      final io = _PdfExportIo(failurePoint: failurePoint, failure: failure);
      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => adapter.execute('ui', 'exportPdf', {}),
          io,
        ),
        throwsA(_pdfSaveFailed),
      );
      expect(await target.readAsString(), 'previous document');
      expect(tempDir.listSync().map((entry) => entry.path), [target.path]);
      if (failurePoint == 'flush') expect(io.flushHandleClosed, isTrue);
    });
  }

  test('יעד שהופיע אחרי הבחירה אינו מקבל הסכמת דריסה בדיעבד', () async {
    final target = File(saveLocation!);
    final io = _PdfExportIo(
      afterWrite: (_) async {
        await target.writeAsString('concurrent document');
      },
    );
    await expectLater(
      IOOverrides.runWithIOOverrides(
        () => adapter.execute('ui', 'exportPdf', {}),
        io,
      ),
      throwsA(_pdfSaveFailed),
    );
    expect(overwritePrompts, isEmpty);
    expect(await target.readAsString(), 'concurrent document');
    expect(tempDir.listSync().map((entry) => entry.path), [target.path]);
  });

  for (final stopAt in ['capture', 'picker']) {
    test('סגירת הדף בזמן $stopAt אינה מפרסמת תשובה מאוחרת', () async {
      final target = File(saveLocation!);
      await target.writeAsString('previous document');
      final started = Completer<void>();
      final release = Completer<void>();
      if (stopAt == 'capture') {
        captureStarted = started;
        captureBarrier = release;
      } else {
        pickerStarted = started;
        pickerBarrier = release;
      }
      final operation = adapter.execute('ui', 'exportPdf', {});
      final outcome = expectLater(operation, throwsA(_revokedAccess));
      try {
        await started.future;
        adapter.releaseRuntime();
      } finally {
        release.complete();
      }
      await outcome;
      expect(overwritePrompts, isEmpty);
      expect(await target.readAsString(), 'previous document');
      expect(tempDir.listSync().map((entry) => entry.path), [target.path]);
    });
  }

  test('אישור דריסה מאוחר אינו מחייה בקשה מדף שנסגר', () async {
    final target = File(saveLocation!);
    await target.writeAsString('previous document');
    afterOverwritePrompt = () async => adapter.releaseRuntime();
    await expectLater(
      adapter.execute('ui', 'exportPdf', {}),
      throwsA(_revokedAccess),
    );
    expect(overwritePrompts, hasLength(1));
    expect(await target.readAsString(), 'previous document');
    expect(tempDir.listSync().map((entry) => entry.path), [target.path]);
  });

  for (final stopAt in ['dispose', 'revoke']) {
    test('$stopAt בזמן כתיבה ממתין לכותב ואז מוחק רק staging', () async {
      final target = File(saveLocation!);
      await target.writeAsString('previous document');
      final io = _PdfExportIo(holdWrite: true);
      final operation = IOOverrides.runWithIOOverrides(
        () => adapter.execute('ui', 'exportPdf', {}),
        io,
      );
      final outcome = expectLater(operation, throwsA(_revokedAccess));
      try {
        final writing = await io.writeStarted.future;
        expect(writing, isNot(target.path));
        expect(await target.readAsString(), 'previous document');
        if (stopAt == 'dispose') {
          adapter.dispose();
        } else {
          PluginRegistryRepository.revokePendingFileAccess('test.plugin');
        }
        expect(await File(writing).exists(), isTrue);
      } finally {
        io.releaseWrite.complete();
      }
      await outcome;
      expect(await target.readAsString(), 'previous document');
      expect(tempDir.listSync().map((entry) => entry.path), [target.path]);
    });
  }

  test(
    'דריסת PDF שומרת הרשאות POSIX פרטיות',
    () async {
      final target = File(saveLocation!);
      await target.writeAsString('previous document');
      posix.chmod(target.path, '600');
      expect(await adapter.execute('ui', 'exportPdf', {}), {
        'saved': true,
        'name': 'דף.pdf',
      });
      expect((await target.stat()).mode & 0x1ff, 0x180);
      expect(await target.readAsBytes(), [37, 80, 68, 70]);
    },
    skip: Platform.isWindows ? 'POSIX permissions only.' : false,
  );

  test('סיומת pdf מושלמת כשהדיאלוג החזיר נתיב בלעדיה', () async {
    saveLocation = '${tempDir.path}/ללא-סיומת';
    final result =
        await adapter.execute('ui', 'exportPdf', {}) as Map<String, dynamic>;
    expect(result['name'], 'ללא-סיומת.pdf');
    expect(File('${tempDir.path}/ללא-סיומת.pdf').existsSync(), isTrue);
  });

  test('בלי ארגומנטי עימוד לא נבנה layout', () async {
    await adapter.execute('ui', 'exportPdf', {});
    expect(capturedLayouts.single, isNull);
  });

  test('ארגומנטי עימוד מפורשים ומועברים ללכידה', () async {
    await adapter.execute('ui', 'exportPdf', {
      'pageSize': 'A5',
      'orientation': 'landscape',
      'marginMm': 10,
      'printBackgrounds': true,
    });

    final layout = capturedLayouts.single!;
    expect(layout.pageWidthMm, 148);
    expect(layout.pageHeightMm, 210);
    expect(layout.landscape, isTrue);
    expect(layout.marginsMm!.top, 10);
    expect(layout.marginsMm!.left, 10);
    expect(layout.printBackgrounds, isTrue);
  });

  test(
    'pageSize כמפה — מידות חופשיות במ"מ, למסמכים בגודל לא סטנדרטי',
    () async {
      await adapter.execute('ui', 'exportPdf', {
        'pageSize': {'widthMm': 210.02, 'heightMm': 297.03},
        'marginMm': 0,
      });

      final layout = capturedLayouts.single!;
      expect(layout.pageWidthMm, 210.02);
      expect(layout.pageHeightMm, 297.03);
      expect(layout.marginsMm!.top, 0);
    },
  );

  test('marginMm כמפה לפי צד; צד חסר הוא אפס', () async {
    await adapter.execute('ui', 'exportPdf', {
      'marginMm': {'top': 20, 'bottom': 15.5},
    });

    final layout = capturedLayouts.single!;
    expect(layout.pageWidthMm, isNull);
    expect(layout.landscape, isNull);
    expect(layout.marginsMm!.top, 20);
    expect(layout.marginsMm!.bottom, 15.5);
    expect(layout.marginsMm!.left, 0);
    expect(layout.marginsMm!.right, 0);
  });

  test('ui.print בלי ארגומנטי עימוד — ברירות המחדל של המנוע', () async {
    await adapter.execute('ui', 'print', {});
    expect(printed.single.layout, isNull);
  });

  test('ui.print מקבל את אותם ארגומנטי עימוד כמו הייצוא', () async {
    await adapter.execute('ui', 'print', {
      'pageSize': 'a4',
      'orientation': 'landscape',
      'marginMm': {'top': 5},
      'printBackgrounds': true,
    });

    final layout = printed.single.layout!;
    expect(layout.pageWidthMm, 210);
    expect(layout.pageHeightMm, 297);
    expect(layout.landscape, isTrue);
    expect(layout.marginsMm!.top, 5);
    expect(layout.marginsMm!.right, 0);
    expect(layout.printBackgrounds, isTrue);
  });

  test('ערך עימוד פסול ב-ui.print נדחה בלי לשלוח להדפסה', () async {
    await expectLater(
      adapter.execute('ui', 'print', {'pageSize': 'a3'}),
      throwsA(predicate((e) => e.toString().contains('error.invalid_params'))),
    );
    expect(printed, isEmpty);
  });

  test('ערכי עימוד פסולים נדחים בלי לפתוח דיאלוג', () async {
    for (final args in [
      {'pageSize': 'a3'},
      {'pageSize': 42},
      {
        'pageSize': {'widthMm': 210},
      },
      {
        'pageSize': {'widthMm': 0, 'heightMm': 297},
      },
      {
        'pageSize': {'widthMm': 210, 'heightMm': 99999},
      },
      {'orientation': 'diagonal'},
      {'marginMm': -1},
      {'marginMm': 500},
      {'marginMm': 'wide'},
      {'printBackgrounds': 'yes'},
    ]) {
      await expectLater(
        adapter.execute('ui', 'exportPdf', args),
        throwsA(
          predicate((e) => e.toString().contains('error.invalid_params')),
        ),
      );
    }
    expect(capturedLayouts, isEmpty);
    expect(savedNames, isEmpty);
  });

  test('ההמרה לאינצ׳ים של מנוע ההדפסה נכונה', () {
    const layout = PluginPdfLayout(
      pageWidthMm: 210,
      pageHeightMm: 297,
      marginsMm: EdgeInsets.all(25.4),
      landscape: false,
      printBackgrounds: false,
    );
    final settings = layout.toPdfConfiguration().settings!;
    expect(settings.pageWidth, closeTo(8.2677, 0.001));
    expect(settings.pageHeight, closeTo(11.6929, 0.001));
    expect(settings.margins!.top, 1.0);
    expect(settings.shouldPrintBackgrounds, isFalse);
  });

  test('בלי פעולת משתמש — print ו-exportPdf נדחים ולא נכתב דבר', () async {
    userActivated = false;

    await expectLater(
      adapter.execute('ui', 'print', {}),
      throwsA(
        predicate(
          (e) => e.toString().contains('error.forbidden: Requires a user'),
        ),
      ),
    );
    await expectLater(
      adapter.execute('ui', 'exportPdf', {}),
      throwsA(
        predicate(
          (e) => e.toString().contains('error.forbidden: Requires a user'),
        ),
      ),
    );

    expect(printed, isEmpty);
    expect(savedNames, isEmpty);
    expect(tempDir.listSync(), isEmpty);
  });

  test('דיאלוג שני בזמן שהראשון פתוח נדחה', () async {
    final gate = Completer<void>();
    final blocked = PluginBridgeAdapter(
      _buildInstalledPlugin(),
      instanceId: 'tab-3',
      dependencies: PluginBridgeDependencies(
        historyBloc: _MockHistoryBloc(),
        tabsBloc: _MockTabsBloc(),
        navigationBloc: _MockNavigationBloc(),
        calendarCubit: _MockCalendarCubit(),
        workspaceBloc: _MockWorkspaceBloc(),
        searchRepository: _MockSearchRepository(),
        personalNotesRepository: _MockPersonalNotesRepository(),
        bookOpenCoordinator: _MockBookOpenCoordinator(),
        themePayloadBuilder: () => <String, dynamic>{},
        showConfirmDialog: ({required title, required content}) async => true,
        showWarningDialog:
            ({required title, required content, required subtitle}) async =>
                true,
        hasUserActivation: (pluginId, instanceId) async => true,
        printPluginPage:
            (pluginId, instanceId, {required jobName, layout}) async {
              await gate.future;
              return true;
            },
      ),
      pluginRepository: _MockPluginRegistryRepository(),
    );

    final first = blocked.execute('ui', 'print', {});
    await expectLater(
      blocked.execute('ui', 'print', {}),
      throwsA(
        predicate((e) => e.toString().contains('A system dialog is already')),
      ),
    );
    gate.complete();
    expect(await first, {'printed': true});
  });

  group('ייצוא דרך שירות המובייל האמיתי', () {
    late _MobileExportBackend backend;
    late AppWindowKeys window;
    final pending = <Future<void>>[];

    Future<void> open(
      WidgetTester tester, {
      bool protected = false,
      bool Function(String)? verifyPassword,
    }) async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      AppWindowKeys.resetForTest();
      window = AppWindowKeys.current;
      backend = _MobileExportBackend();
      pending.clear();
      final settings = _MockSettingsBloc();
      whenListen(
        settings,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial().copyWith(
          protectedModeEnabled: protected,
        ),
      );
      final service = MobilePdfExportService.withBackend(
        platform: MobilePdfExportPlatform.ios,
        backend: backend,
        temporaryDirectory: () async => tempDir,
      );
      late BuildContext context;
      await tester.pumpWidget(
        RepositoryProvider<SettingsRepository>.value(
          value: _ExportSettingsRepository(protected, verifyPassword),
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
              home: Builder(
                builder: (value) {
                  context = value;
                  return const Scaffold(body: SizedBox());
                },
              ),
            ),
          ),
        ),
      );
      adapter.dispose();
      adapter = buildAdapter(context: context, mobileService: service);
      addTearDown(() async {
        adapter.dispose();
        backend.finishPending();
        UiSnack.hide(window: window);
        try {
          window.navigator.currentState?.popUntil((route) => route.isFirst);
          await tester.pump();
          await tester.pumpWidget(const SizedBox());
          for (final future in pending) {
            await _settleMobile(tester, future);
          }
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        } finally {
          await settings.close();
        }
      });
    }

    Future<dynamic> start({String fileName = 'דף עברי'}) {
      final result = adapter.execute('ui', 'exportPdf', {'fileName': fileName});
      pending.add(
        result.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return result;
    }

    for (final providerName in ['שם הספק.pdf', null]) {
      testWidgets('הצלחה מחזירה רק שם ספק מאומת: $providerName', (
        tester,
      ) async {
        await open(tester);
        final result = start();
        await _waitForMobile(tester, () => backend.requests.length == 1);
        final request = backend.requests.single;
        expect(request.fileName, 'דף עברי.pdf');
        expect(request.sourcePath, isNot(saveLocation));
        expect(
          await tester.runAsync(() => File(request.sourcePath).readAsBytes()),
          [37, 80, 68, 70],
        );
        expect(savedNames, isEmpty);
        backend.complete(
          MobilePdfExportStatus.saved,
          displayName: providerName,
        );
        expect(await _settleMobile(tester, result), {
          'saved': true,
          'name': providerName,
        });
        expect(File(request.sourcePath).existsSync(), isFalse);
        expect(File(request.sourcePath).parent.existsSync(), isFalse);
        expect(File(saveLocation!).existsSync(), isFalse);
        expect(overwritePrompts, isEmpty);
      });
    }

    for (final outcome in [
      MobilePdfExportStatus.cancelled,
      MobilePdfExportStatus.saved,
    ]) {
      testWidgets('סגירה מחזיקה staging עד terminal מסוג ${outcome.name}', (
        tester,
      ) async {
        await open(tester);
        var completed = false;
        final result = start()..then<void>((_) => completed = true);
        await _waitForMobile(tester, () => backend.requests.length == 1);
        final request = backend.requests.single;
        adapter.releaseRuntime();
        adapter.dispose();
        await _waitForMobile(tester, () => backend.cancellations.length == 1);
        await tester.pump();
        expect(completed, isFalse);
        expect(File(request.sourcePath).existsSync(), isTrue);
        expect(backend.cancellations, [request.operationId]);
        backend.complete(outcome, displayName: 'שם בפועל.pdf');
        expect(await _settleMobile(tester, result), {
          'saved': outcome == MobilePdfExportStatus.saved,
          'name': outcome == MobilePdfExportStatus.saved
              ? 'שם בפועל.pdf'
              : null,
        });
        expect(File(request.sourcePath).existsSync(), isFalse);
        expect(savedNames, isEmpty);
      });
    }

    testWidgets('שלילת הרשאה מבקשת ביטול ושומרת staging עד תוצאת iOS', (
      tester,
    ) async {
      await open(tester);
      var completed = false;
      final result = start()..then<void>((_) => completed = true);
      await _waitForMobile(tester, () => backend.requests.length == 1);
      final request = backend.requests.single;

      PluginRegistryRepository.revokePendingFileAccess('another.plugin');
      await tester.pump();
      expect(backend.cancellations, isEmpty);
      PluginRegistryRepository.revokePendingFileAccess('test.plugin');
      await _waitForMobile(tester, () => backend.cancellations.length == 1);
      expect(backend.cancellations, [request.operationId]);
      expect(completed, isFalse);
      expect(File(request.sourcePath).existsSync(), isTrue);

      backend.complete(MobilePdfExportStatus.cancelled);
      expect(await _settleMobile(tester, result), {
        'saved': false,
        'name': null,
      });
      expect(File(request.sourcePath).existsSync(), isFalse);
    });

    testWidgets('שארית אחרי dispose מוזהרת למשתמש בלי URI בתשובת RPC', (
      tester,
    ) async {
      await open(tester);
      final result = start();
      await _waitForMobile(tester, () => backend.requests.length == 1);
      adapter.dispose();
      await _waitForMobile(tester, () => backend.cancellations.length == 1);
      backend.complete(
        MobilePdfExportStatus.failed,
        residualDocument: 'content://private-provider/partial-document',
        residualDisplayName: 'עותק חלקי.pdf',
      );
      expect(await _settleMobile(tester, result), {
        'saved': false,
        'name': null,
      });
      await tester.pump();
      expect(
        find.text(PdfMessages.mobilePdfExportResidual('עותק חלקי.pdf')),
        findsOneWidget,
      );
      expect(find.textContaining('private-provider'), findsNothing);
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(savedNames, isEmpty);
      UiSnack.hide(window: window);
    });

    for (final transportError in [false, true]) {
      testWidgets('כשל native אינו חוזר לכתיבה ישירה; retry: $transportError', (
        tester,
      ) async {
        await open(tester);
        final first = start();
        await _waitForMobile(tester, () => backend.requests.length == 1);
        if (transportError) {
          backend.pending.last.completeError(
            StateError('private diagnostic content://private-provider/failure'),
          );
        } else {
          backend.complete(MobilePdfExportStatus.failed);
        }
        expect(await _settleMobile(tester, first), {
          'saved': false,
          'name': null,
        });
        await tester.pump();
        expect(find.text(PdfMessages.mobilePdfSaveFailed), findsOneWidget);
        expect(find.textContaining('private diagnostic'), findsNothing);
        expect(savedNames, isEmpty);
        expect(File(saveLocation!).existsSync(), isFalse);
        expect(File(backend.requests.first.sourcePath).existsSync(), isFalse);
        final second = start();
        await _waitForMobile(tester, () => backend.requests.length == 2);
        backend.complete(MobilePdfExportStatus.saved, displayName: 'retry.pdf');
        expect(await _settleMobile(tester, second), {
          'saved': true,
          'name': 'retry.pdf',
        });
        UiSnack.hide(window: window);
      });
    }

    testWidgets('ללא פעולת משתמש אין capture או פתיחת בורר native', (
      tester,
    ) async {
      await open(tester);
      userActivated = false;
      final error = await _settleMobile(tester, _mobileError(start()));
      expect(
        error,
        predicate<Object>(
          (error) => '$error'.contains('Requires a user gesture'),
        ),
      );
      expect(capturedLayouts, isEmpty);
      expect(backend.requests, isEmpty);
      expect(savedNames, isEmpty);
      expect(tempDir.listSync(), isEmpty);
    });

    testWidgets('ביטול אימות סייפר מונע staging ופתיחת בורר native', (
      tester,
    ) async {
      await open(tester, protected: true);
      final result = start();
      await _waitForMobile(
        tester,
        () => find.byType(SaferModePasswordDialog).evaluate().isNotEmpty,
      );
      expect(backend.requests, isEmpty);
      expect(tempDir.listSync(), isEmpty);
      await tester.tap(find.text('ביטול'));
      expect(await _settleMobile(tester, result), {
        'saved': false,
        'name': null,
      });
      expect(backend.requests, isEmpty);
      expect(savedNames, isEmpty);
    });

    testWidgets('אימות סייפר מאוחר אינו מחייה בקשה מדף שהשתחרר', (
      tester,
    ) async {
      await open(
        tester,
        protected: true,
        verifyPassword: (_) {
          adapter.releaseRuntime();
          return true;
        },
      );
      final failure = _mobileError(start());
      await _waitForMobile(
        tester,
        () => find.byType(SaferModePasswordDialog).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byType(TextField), 'test password');
      await tester.tap(find.text('אישור'));
      expect(await _settleMobile(tester, failure), _revokedAccess);
      expect(backend.requests, isEmpty);
      expect(savedNames, isEmpty);
      expect(tempDir.listSync(), isEmpty);
    });
  });

  test('ui.print רשומה בגשר ואינה דורשת הרשאת manifest', () {
    expect(
      PluginBridgeHandler.methodPermissions.containsKey('ui.print'),
      isTrue,
    );
    expect(
      PluginBridgeHandler.methodPermissions['ui.print'],
      PluginBridgeHandler.noManifestPermission,
    );
  });
}

final _revokedAccess = predicate<Object>(
  (error) =>
      error.toString().contains('error.unavailable: file access revoked'),
);

final _pdfSaveFailed = predicate<Object>(
  (error) =>
      error.toString() == 'Exception: error.internal: failed to save the PDF',
);

final class _PdfExportIo extends IOOverrides {
  _PdfExportIo({
    this.failurePoint,
    this.failure,
    this.afterWrite,
    this.holdWrite = false,
  });

  final String? failurePoint;
  final Object? failure;
  final Future<void> Function(String path)? afterWrite;
  final bool holdWrite;
  final writeStarted = Completer<String>();
  final releaseWrite = Completer<void>();
  bool flushHandleClosed = false;

  @override
  File createFile(String path) => _PdfExportFile(super.createFile(path), this);
}

class _PdfExportFile implements File {
  _PdfExportFile(this.base, this.io);

  final File base;
  final _PdfExportIo io;

  @override
  String get path => base.path;

  @override
  File get absolute => base.absolute;

  @override
  Directory get parent => base.parent;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await base.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    if (io.failurePoint == 'write' || io.holdWrite) {
      await base.writeAsBytes(bytes.take(2).toList(), mode: mode, flush: flush);
      if (io.failurePoint == 'write') throw io.failure!;
      io.writeStarted.complete(path);
      await io.releaseWrite.future;
    }
    await base.writeAsBytes(bytes, mode: mode, flush: flush);
    await io.afterWrite?.call(path);
    return this;
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    final handle = await base.open(mode: mode);
    return io.failurePoint == 'flush' ? _PdfExportHandle(handle, io) : handle;
  }

  @override
  Future<File> rename(String newPath) async {
    if (io.failurePoint == 'rename') throw io.failure!;
    return base.rename(newPath);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      base.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PdfExportHandle implements RandomAccessFile {
  _PdfExportHandle(this.base, this.io);

  final RandomAccessFile base;
  final _PdfExportIo io;

  @override
  Future<RandomAccessFile> flush() async => throw io.failure!;

  @override
  Future<void> close() async {
    await base.close();
    io.flushHandleClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _ExportSettingsRepository extends Mock implements SettingsRepository {
  _ExportSettingsRepository(this.protected, this.verify);

  final bool protected;
  final bool Function(String)? verify;

  @override
  bool hasProtectedModePassword() => protected;

  @override
  bool verifyProtectedModePassword(String password) =>
      verify?.call(password) ?? false;
}

class _MobileExportBackend implements MobilePdfExportBackend {
  final requests = <MobilePdfExportRequest>[];
  final cancellations = <String>[];
  final pending = <Completer<MobilePdfExportResult>>[];

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
    return true;
  }

  void complete(
    MobilePdfExportStatus status, {
    String? displayName,
    String? residualDocument,
    String? residualDisplayName,
  }) {
    pending.last.complete(
      MobilePdfExportResult(
        operationId: requests.last.operationId,
        status: status,
        documentUri: status == MobilePdfExportStatus.saved
            ? 'file:///private-provider/export/document.pdf'
            : null,
        displayName: displayName,
        errorCode: status == MobilePdfExportStatus.failed
            ? 'copy_failed'
            : null,
        errorMessage: status == MobilePdfExportStatus.failed
            ? 'private diagnostic content://private-provider/failure'
            : null,
        residualDocument: residualDocument,
        residualDisplayName: residualDisplayName,
        cleanupStatus: residualDocument == null
            ? MobilePdfExportCleanupStatus.notNeeded
            : MobilePdfExportCleanupStatus.failed,
      ),
    );
  }

  void finishPending() {
    for (var i = 0; i < pending.length; i++) {
      if (!pending[i].isCompleted) {
        pending[i].complete(
          MobilePdfExportResult(
            operationId: requests[i].operationId,
            status: MobilePdfExportStatus.cancelled,
          ),
        );
      }
    }
  }
}

Future<void> _waitForMobile(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'The plugin mobile export did not settle.');
}

Future<T> _settleMobile<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  future.then<void>(
    (_) => done = true,
    onError: (Object _, StackTrace _) => done = true,
  );
  await _waitForMobile(tester, () => done);
  return future;
}

Future<Object?> _mobileError(Future<dynamic> future) => future.then<Object?>(
  (_) => null,
  onError: (Object error, StackTrace _) => error,
);

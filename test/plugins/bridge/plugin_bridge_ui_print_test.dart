import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
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
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

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
  late List<({String pluginId, String instanceId, String jobName})> printed;
  late bool printResult;
  late bool userActivated;
  late List<String> savedNames;
  late List<PluginPdfLayout?> capturedLayouts;
  late String? saveLocation;
  late Directory tempDir;
  late PluginBridgeAdapter adapter;

  setUp(() {
    printed = [];
    printResult = true;
    userActivated = true;
    savedNames = [];
    capturedLayouts = [];
    tempDir = Directory.systemTemp.createTempSync('otzaria_export_pdf');
    saveLocation = '${tempDir.path}/דף.pdf';
    adapter = PluginBridgeAdapter(
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
        printPluginPage: (pluginId, instanceId, {required jobName}) async {
          printed.add((
            pluginId: pluginId,
            instanceId: instanceId,
            jobName: jobName,
          ));
          return printResult;
        },
        capturePluginPagePdf: (pluginId, instanceId, {layout}) async {
          capturedLayouts.add(layout);
          return Uint8List.fromList(const [37, 80, 68, 70]);
        },
        hasUserActivation: (pluginId, instanceId) async => userActivated,
        pickSaveLocation:
            ({required suggestedName, allowedExtensions, title}) async {
              savedNames.add(suggestedName);
              return saveLocation;
            },
      ),
      pluginRepository: _MockPluginRegistryRepository(),
    );
  });

  tearDown(() {
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

  test('ערכי עימוד פסולים נדחים בלי לפתוח דיאלוג', () async {
    for (final args in [
      {'pageSize': 'a3'},
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
        printPluginPage: (pluginId, instanceId, {required jobName}) async {
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

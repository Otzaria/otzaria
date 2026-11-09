// Opt-in real-app benchmark. See tool/perf_probe/README.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/main.dart' as app;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:path/path.dart' as p;
import 'package:positioned_sliver_list/positioned_list.dart';

import 'support/perf_fixture.dart';
import 'support/perf_recorder.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final outputPath = perfOption(
    'PERF_OUTPUT_DIR',
    const String.fromEnvironment('PERF_OUTPUT_DIR'),
  );
  final dataPath = perfOption(
    'PERF_DATA_DIR',
    const String.fromEnvironment('PERF_DATA_DIR'),
  );
  final cacheState = perfOption(
    'PERF_CACHE_STATE',
    const String.fromEnvironment('PERF_CACHE_STATE', defaultValue: 'cold'),
  );
  final launchIndex = int.parse(
    perfOption(
      'PERF_LAUNCH_INDEX',
      const String.fromEnvironment('PERF_LAUNCH_INDEX', defaultValue: '0'),
    ),
  );
  final warmup = int.parse(
    perfOption(
      'PERF_WARMUP',
      const String.fromEnvironment('PERF_WARMUP', defaultValue: '1'),
    ),
  );
  final repetitions = int.parse(
    perfOption(
      'PERF_REPETITIONS',
      const String.fromEnvironment('PERF_REPETITIONS', defaultValue: '5'),
    ),
  );
  final preparationOnly =
      perfOption(
        'PERF_PREPARE_ONLY',
        const String.fromEnvironment('PERF_PREPARE_ONLY', defaultValue: '0'),
      ) ==
      '1';
  final output = Directory(outputPath);
  final recorderDone = Completer<void>();
  PerfRecorder? recorder;
  Object? runError;
  var canWriteOutput = false;
  String? fixtureId;
  FlutterExceptionHandler? previousFlutterError;
  bool Function(Object, StackTrace)? previousPlatformError;
  var installedErrorCapture = false;

  unawaited(
    binding.allTestsPassed.future.then((passed) async {
      await recorderDone.future;
      if (!canWriteOutput) {
        return;
      }
      final success = passed && runError == null;
      await File(p.join(output.path, 'phases.jsonl')).writeAsString(
        '${jsonEncode({'type': 'done', 'launchIndex': launchIndex, 'status': success ? 'passed' : 'failed', 'endedAt': DateTime.now().millisecondsSinceEpoch})}\n',
        mode: FileMode.append,
        flush: true,
      );
      final completion = File(p.join(output.path, 'completion.pending'));
      await completion.writeAsString(
        jsonEncode({
          'status': success ? 'passed' : 'failed',
          'error': runError?.toString(),
          'fixtureId': fixtureId,
          'preparationOnly': preparationOnly,
          'testFailures': [
            for (final failure in binding.failureMethodsDetails)
              failure.details,
          ],
        }),
        flush: true,
      );
      await completion.rename(p.join(output.path, 'completion.json'));
    }),
  );

  testWidgets('reproducible resource probe', timeout: const Timeout(Duration(minutes: 20)), (
    tester,
  ) async {
    try {
      if (!p.isAbsolute(outputPath) ||
          !p.isAbsolute(dataPath) ||
          p.equals(outputPath, dataPath) ||
          p.isWithin(dataPath, outputPath) ||
          p.isWithin(outputPath, dataPath)) {
        throw ArgumentError(
          'Set separate absolute PERF_OUTPUT_DIR and PERF_DATA_DIR paths.',
        );
      }
      if (!['cold', 'warm'].contains(cacheState) ||
          warmup < 0 ||
          warmup > 10 ||
          repetitions < 1 ||
          repetitions > 100) {
        throw ArgumentError(
          'Invalid cache state, warmup (0..10), or repetitions (1..100).',
        );
      }
      await output.create(recursive: true);
      final journal = File(p.join(output.path, 'phases.jsonl'));
      if (await journal.exists() ||
          await File(p.join(output.path, 'completion.json')).exists()) {
        throw StateError('The output directory already contains a run.');
      }
      canWriteOutput = true;
      final fixture = PerfFixture(Directory(dataPath));
      await fixture.prepare(preparationOnly: preparationOnly);
      fixtureId = fixture.id;
      final rec = recorder = PerfRecorder(
        journal,
        binding,
        launchIndex: launchIndex,
      );
      rec.write({
        'type': 'meta',
        'schemaVersion': 2,
        'protocolVersion': 2,
        'fixtureId': fixture.id,
        'preparationOnly': preparationOnly,
        'buildMode': perfBuildMode,
        'cacheState': cacheState,
        'warmup': warmup,
        'repetitions': repetitions,
        'pid': pid,
        'cores': Platform.numberOfProcessors,
        'startedAt': DateTime.now().millisecondsSinceEpoch,
        'fixtureBooks': perfBooks,
        'limitations': [
          'Cold means a fresh app data directory; OS filesystem caches are not evicted.',
          'Startup begins at Dart main; native engine/process initialization is separate.',
          'Condition polling resolution is 16 ms; frames use engine timestamps.',
          'Heap samples are outside action latency, without forced garbage collection.',
          'Private bytes are not native-only memory; RSS minus Dart heap is not computed.',
        ],
      });
      if (preparationOnly) {
        return;
      }
      late _Scenario scenario;
      previousFlutterError = FlutterError.onError;
      previousPlatformError = PlatformDispatcher.instance.onError;
      final unexpectedErrors = <String>[];
      void onFlutterError(FlutterErrorDetails details) {
        unexpectedErrors.add(details.exceptionAsString());
        previousFlutterError?.call(details);
      }

      bool onPlatformError(Object error, StackTrace stack) {
        onFlutterError(FlutterErrorDetails(exception: error, stack: stack));
        return true;
      }

      void captureErrors() {
        FlutterError.onError = onFlutterError;
        PlatformDispatcher.instance.onError = onPlatformError;
        installedErrorCapture = true;
      }

      rec.verifyAction = () {
        if (unexpectedErrors.isNotEmpty) {
          throw StateError('Unhandled app error: ${unexpectedErrors.first}');
        }
      };
      final errorsFile = ErrorLogFile.resolveFile();
      final errorsBefore = await errorsFile.exists()
          ? await errorsFile.readAsString()
          : '';
      captureErrors();
      await rec.phase('startup.first_content', () async {
        app.main(const []);
        await _wait(
          () {
            captureErrors();
            return find.byType(App).evaluate().isNotEmpty &&
                StartupTimeline.instance.toJson()['revealMs'] != null;
          },
          'usable app window',
          timeout: const Duration(minutes: 3),
        );
        final context = tester.element(find.byType(App));
        final library = await DataRepository.instance.library;
        scenario = _Scenario(tester, context, rec, library, fixture);
        await scenario.openText(perfBooks.keys.first);
      }, sampleHeap: false);
      final startup = StartupTimeline.instance;
      final revealMs = startup.toJson()['revealMs'] as int;
      final startupAt = startup.startedAt!.millisecondsSinceEpoch;
      rec.write({
        'type': 'phase',
        'name': 'startup.window_useful',
        'status': 'passed',
        'warmup': false,
        'iteration': 0,
        'startMs': startupAt,
        'endMs': startupAt + revealMs,
        'durationMs': revealMs,
        'frames': {
          'count': 0,
          'buildMs': [],
          'rasterMs': [],
          'totalMs': [],
          'unavailableReason':
              'StartupTimeline endpoint; frames are in startup.first_content.',
        },
        'details': startup.toJson(),
      });
      final view = tester.view;
      final settings = scenario.context.read<SettingsBloc>().state;
      rec.write({
        'type': 'meta',
        'schemaVersion': 2,
        'protocolVersion': 2,
        'viewport': {
          'width': view.physicalSize.width / view.devicePixelRatio,
          'height': view.physicalSize.height / view.devicePixelRatio,
          'devicePixelRatio': view.devicePixelRatio,
        },
        'settings': {
          'fontFamily': settings.fontFamily,
          'fontSize': settings.fontSize,
          'showTeamim': settings.showTeamim,
          'offline': true,
          'fixtureBooks': perfBooks,
          'scrollSteps': 60,
          'scrollPixels': 30,
          'pollIntervalMs': 16,
          'rssIntervalMs': 250,
          'searchQuery': perfQuery,
          'searchMode': 'exact',
          'searchResultLimit': 100,
          'searchGrouping': 'none',
        },
      });
      rec.counters = scenario.counters;
      await rec.heap.connect();
      await scenario.closeTabs();
      await rec.phase(
        'index.fixture_prepare',
        scenario.indexFixture,
        warmup: true,
      );
      await scenario.installPlugin();
      for (var round = 0; round < warmup + repetitions; round++) {
        scenario.iteration = round < warmup ? round : round - warmup;
        scenario.warmup = round < warmup;
        await scenario.run();
      }
      final errorsAfter = await errorsFile.exists()
          ? await errorsFile.readAsString()
          : '';
      final newErrors = errorsAfter.startsWith(errorsBefore)
          ? errorsAfter.substring(errorsBefore.length)
          : errorsAfter;
      if (RegExp(
        r'^=== (FlutterError|Unhandled Error)',
        multiLine: true,
      ).hasMatch(newErrors)) {
        throw StateError(
          'The app logged an unhandled error while installing its error handlers.',
        );
      }
      rec.verifyAction?.call();
      rec.skip(
        'windows.native_open_close',
        'installWindowingOwner rejects TestPlatformDispatcher (hasRealPlatformDispatcher=false). Its synthetic engineId is not a native pointer; real-app diagnostics are required.',
      );
      rec.skip(
        'queues.depth',
        'The application exposes active work and indexing state, not complete queue depths.',
      );
    } catch (error) {
      runError = error;
      rethrow;
    } finally {
      if (installedErrorCapture) {
        FlutterError.onError = previousFlutterError;
        PlatformDispatcher.instance.onError = previousPlatformError;
      }
      try {
        await recorder?.dispose();
      } finally {
        recorderDone.complete();
      }
    }
  });
}

Future<void> _wait(
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed >= timeout) {
      throw TimeoutException('Waiting for $description', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

class _Scenario {
  _Scenario(this.tester, this.context, this.rec, this.library, this.fixture);
  final WidgetTester tester;
  final BuildContext context;
  final PerfRecorder rec;
  final Library library;
  final PerfFixture fixture;
  int iteration = 0;
  bool warmup = false;
  TabsBloc get tabs => context.read<TabsBloc>();
  IndexingBloc get indexing => context.read<IndexingBloc>();

  Map<String, Object?> counters() => {
    'openTabs': tabs.state.tabs.length,
    'activeWork': context
        .read<WorkStatusCubit>()
        .state
        .items
        .values
        .where((item) => item.kind == WorkStatusKind.running)
        .length,
    'indexingActive': TantivyDataProvider.instance.isIndexing.value ? 1 : 0,
    'schedulerCallbacks': tester.binding.transientCallbackCount,
    'flutterViews': PlatformDispatcher.instance.views.length,
    'queueDepth': null,
  };

  Future<void> phase(
    String name,
    Future<void> Function() action, {
    Map<String, Object?>? details,
  }) => rec.phase(
    name,
    action,
    warmup: warmup,
    iteration: iteration,
    details: details,
  );

  Future<void> run() async {
    for (final title in perfBooks.keys) {
      final kind = switch (perfBooks[title]) {
        128 => 'short',
        4096 => 'medium',
        _ => 'long',
      };
      await phase('book.$kind.open', () async {
        await openText(title);
      });
      final tab = tabs.state.currentTab as TextBookTab;
      await phase('book.$kind.scroll', () async {
        // Wide layouts make the main window's page switcher vertical too.
        final scrollable = find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is ScrollablePositionedList &&
                identical(
                  widget.itemScrollController,
                  tab.lines.itemController,
                ),
          ),
          matching: find.byType(Scrollable),
        );
        final candidates = tester
            .stateList<ScrollableState>(scrollable)
            .where(
              (state) =>
                  state.position.axis == Axis.vertical &&
                  state.position.maxScrollExtent > 500,
            )
            .toList();
        if (candidates.length != 1) {
          throw StateError(
            'Expected exactly one vertical reader scrollable, found ${candidates.length}.',
          );
        }
        final position = candidates.single.position;
        for (var step = 0; step < 60; step++) {
          position.jumpTo(
            (position.pixels + 30).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
          await tester.pump();
        }
      }, details: {'steps': 60, 'pixelsPerStep': 30});
      for (final fraction in [0.75, 0.1]) {
        final target = (perfBooks[title]! * fraction).floor();
        final direction = fraction == 0.75 ? 'forward' : 'backward';
        await phase('book.$kind.jump_$direction', () async {
          await tab.lines
              .jumpToLine(target)
              .timeout(const Duration(seconds: 45));
          await waitText(tab, target);
        }, details: {'line': target, 'fraction': fraction});
      }
      await phase('book.$kind.close', closeTabs);
    }
    await phase('search.normal', search);
    await closeTabs();
    await _searchWhileIndexing();
    await closeTabs();
    await _notes();
    await _plugin();
    await _preview();
    await phase('lifecycle.tabs_cycle', () async {
      await openText(perfBooks.keys.first);
      await openText(perfBooks.keys.last);
      tabs.add(const SetCurrentTab(0));
      await tester.pump();
      await closeTabs();
    });
    await phase(
      'lifecycle.idle_after_close',
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
  }

  Future<TextBookTab> openText(String title) async {
    final book = library.getAllBooks().whereType<TextBook>().singleWhere(
      (book) => book.title == title,
    );
    final tab = TextBookTab(
      book: book,
      index: 1,
      commentators: const [],
      splitedView: false,
      showPageShapeView: false,
    );
    context.read<NavigationBloc>().add(NavigateToScreen(Screen.reading));
    tabs.add(AddTab(tab));
    await _wait(
      () => identical(tabs.state.currentTab, tab),
      'selected text tab',
    );
    await waitText(tab, 1);
    return tab;
  }

  Future<void> waitText(TextBookTab tab, int line) async {
    await _wait(() {
      final state = tab.bloc.state;
      return state is TextBookLoaded &&
          state.isContentLineLoaded(line) &&
          line < state.content.length &&
          state.content[line].isNotEmpty &&
          tab.lines.isAttached &&
          !tab.lines.hasPendingTarget &&
          !tab.lines.isNavigating;
    }, 'loaded line $line');
    await tester.pump();
    await _wait(
      () => tab.lines.position.value?.visibleLines.contains(line) == true,
      'visible line $line',
    );
  }

  Future<void> closeTabs() async {
    final closing = tabs.state.tabs.toList();
    tabs.add(CloseAllTabs());
    await _wait(() => tabs.state.tabs.isEmpty, 'tabs closed');
    await tester.pump();
    await _wait(
      () => closing.every(
        (tab) => switch (tab) {
          TextBookTab() => tab.bloc.isClosed,
          SearchingTab() => tab.searchBloc.isClosed,
          ToolTab() =>
            PluginRuntimeDispatcher.instance.controllerOf(
                  tab.toolId,
                  instanceId: tab.instanceId,
                ) ==
                null,
          _ => false,
        },
      ),
      'tab controllers disposed',
    );
  }

  Future<void> indexFixture() async {
    final done = Completer<void>();
    indexing.add(StartIndexing(library, onSettled: done.complete));
    await done.future.timeout(const Duration(minutes: 3));
    if (indexing.state case IndexingError(:final error)) {
      throw StateError(error);
    }
    if (indexing.state case IndexingComplete(:final failures)) {
      if (failures.isNotEmpty) {
        throw StateError('Fixture indexing had ${failures.length} failures.');
      }
    } else {
      throw StateError('Fixture indexing did not complete: ${indexing.state}.');
    }
  }

  Future<void> search() async {
    final tab = SearchingTab(
      SearchingTab.titleForQuery(perfQuery),
      perfQuery,
      initialConfiguration: const SearchConfiguration(
        searchMode: SearchMode.exact,
        distance: 0,
        numResults: 100,
        resultGrouping: ResultGroupingMode.none,
        anyOrder: false,
      ),
    );
    context.read<NavigationBloc>().add(NavigateToScreen(Screen.reading));
    tabs.add(AddTab(tab));
    await _wait(() {
      final state = tab.searchBloc.state;
      if (state.errorMessage case final error?) {
        throw StateError(error);
      }
      return identical(tabs.state.currentTab, tab) &&
          state.searchQuery == perfQuery &&
          !state.isLoading &&
          !state.isCounting &&
          state.results.isNotEmpty;
    }, 'complete search results');
    if (tab.searchBloc.state.resultsTruncated) {
      throw StateError('The search returned a truncated result set.');
    }
    await tester.pump();
  }

  Future<void> _searchWhileIndexing() async {
    final done = Completer<void>();
    var completed = false;
    indexing.add(
      RunIndexing(
        library,
        changedBooks: library.getAllBooks().whereType<TextBook>().toList(),
        onSettled: () {
          completed = true;
          done.complete();
        },
      ),
    );
    await _wait(
      () => completed || TantivyDataProvider.instance.isIndexing.value,
      'indexing started',
      timeout: const Duration(minutes: 3),
    );
    try {
      await phase('search.while_indexing', () async {
        if (!TantivyDataProvider.instance.isIndexing.value) {
          throw const PerfSkipped(
            'Indexing finished before the search could overlap.',
          );
        }
        await search();
        if (!TantivyDataProvider.instance.isIndexing.value) {
          throw const PerfSkipped(
            'Indexing did not remain active for the whole measured search.',
          );
        }
      });
    } finally {
      await done.future.timeout(const Duration(minutes: 3));
      if (indexing.state case IndexingError(:final error)) {
        throw StateError(error);
      }
      if (indexing.state case IndexingComplete(:final failures)) {
        if (failures.isNotEmpty) {
          throw StateError('Concurrent indexing failed.');
        }
      } else {
        throw StateError(
          'Concurrent indexing did not complete: ${indexing.state}.',
        );
      }
    }
  }

  NavigatorState get navigator =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  Future<void> _notes() async {
    await phase('notes.open', () async {
      unawaited(
        showDialog<void>(
          context: navigator.context,
          builder: (_) => const PersonalNoteEditorDialog(
            initialContent: 'טקסט קבוע לבדיקת עורך ההערות',
          ),
        ),
      );
      await _wait(
        () => find.byType(PersonalNoteEditorBody).evaluate().length == 1,
        'note editor',
      );
      await tester.pump();
    });
    final body = tester.widget<PersonalNoteEditorBody>(
      find.byType(PersonalNoteEditorBody),
    );
    final controller = body.controller.quillController;
    body.focusNode.requestFocus();
    await tester.pump();
    await phase('notes.edit', () async {
      const added = ' תוספת בדיקה עם מספרים 0123456789';
      controller.replaceText(
        0,
        0,
        added,
        TextSelection.collapsed(offset: added.length),
      );
      await tester.pump();
      if (!controller.document.toPlainText().startsWith(added)) {
        throw StateError('The note edit was not applied.');
      }
    });
    await phase('notes.caret', () async {
      for (var i = 0; i < 12; i++) {
        final before = controller.selection;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        if (controller.selection == before) {
          throw StateError('The caret did not move.');
        }
      }
    }, details: {'arrowKeyCount': 12});
    await phase('notes.close', () async {
      navigator.pop();
      await _wait(
        () => find.byType(PersonalNoteEditorBody).evaluate().isEmpty,
        'note editor disposed',
      );
    });
  }

  Future<void> installPlugin() async {
    final now = DateTime.utc(2020);
    final manifest = PluginManifest.fromJson({
      'schemaVersion': 1,
      'id': perfPluginId,
      'name': 'תוסף מדידה',
      'version': '1.0.0',
      'entrypoint': 'index.html',
      'permissions': <String>[],
      'network': {'enabled': false},
    });
    await PluginRegistryRepository().savePlugin(
      InstalledPlugin(
        pluginId: perfPluginId,
        name: manifest.name,
        version: manifest.version,
        installPath: fixture.pluginPath,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: manifest,
        installedAt: now,
        updatedAt: now,
      ),
    );
    final plugins = context.read<PluginSystemBloc>();
    plugins.add(LoadPlugins());
    await _wait(() {
      final state = plugins.state;
      return state is PluginSystemLoaded &&
          state.plugins.any(
            (plugin) => plugin.pluginId == perfPluginId && plugin.enabled,
          );
    }, 'local plugin registered');
  }

  Future<void> _plugin() async {
    final tab = ToolTab(toolId: perfPluginId, title: 'תוסף מדידה');
    final dispatcher = PluginRuntimeDispatcher.instance;
    await phase(
      'plugin.open',
      () async {
        tabs.add(AddTab(tab));
        context.read<NavigationBloc>().add(NavigateToScreen(Screen.reading));
        await _wait(
          () =>
              dispatcher.controllerOf(
                perfPluginId,
                instanceId: tab.instanceId,
              ) !=
              null,
          'plugin WebView controller',
          timeout: const Duration(seconds: 60),
        );
        final clock = Stopwatch()..start();
        var ready = false;
        while (!ready) {
          if (clock.elapsed > const Duration(seconds: 45)) {
            throw TimeoutException('Plugin first DOM paint');
          }
          final controller = dispatcher.controllerOf(
            perfPluginId,
            instanceId: tab.instanceId,
          );
          if (controller == null) {
            throw StateError(
              'The plugin controller detached before readiness.',
            );
          }
          ready =
              await controller
                  .evaluateJavascript(source: 'window.perfReady === true')
                  .timeout(const Duration(seconds: 5)) ==
              true;
          if (!ready) {
            await Future<void>.delayed(const Duration(milliseconds: 16));
          }
        }
      },
      details: {
        'javascriptTimeoutSeconds': 5,
        'readiness': 'double-requestAnimationFrame',
      },
    );
    await phase('plugin.close', () async {
      await closeTabs();
      await _wait(
        () =>
            dispatcher.controllerOf(perfPluginId, instanceId: tab.instanceId) ==
            null,
        'plugin detached',
      );
    });
  }

  Future<void> _preview() async {
    await phase('pdf.preview_first_page', () async {
      unawaited(
        showDialog<void>(
          context: navigator.context,
          builder: (_) => PrintingScreen(
            data: Future.value(List.generate(24, perfLine).join('\n')),
            bookId: 'performance-preview',
            endLine: 24,
          ),
        ),
      );
      await _wait(
        () => find
            .descendant(
              of: find.byType(PrintingScreen),
              matching: find.byWidgetPredicate(
                (widget) => widget is RawImage && widget.image != null,
              ),
            )
            .evaluate()
            .isNotEmpty,
        'decoded first PDF preview page',
        timeout: const Duration(seconds: 90),
      );
      await tester.pump();
    });
    await phase('pdf.preview_close', () async {
      navigator.pop();
      await _wait(
        () => find.byType(PrintingScreen).evaluate().isEmpty,
        'PDF preview disposed',
      );
    });
  }
}

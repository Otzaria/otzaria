// Opt-in real-app benchmark. See tool/perf_probe/README.md.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart' as pdf_events;
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_book_render_observation.dart';
import 'package:otzaria/pdf_book/view/book_view_turn_button.dart';
import 'package:otzaria/pdf_book/utils/pdf_image_budget.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_thumbnails_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:path/path.dart' as p;
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../tool/perf_probe/src/pdf_reader_case.dart';
import '../../tool/perf_probe/src/pdf_image_budget.dart';
import 'perf_fixture.dart';
import 'perf_pdf_image_budget.dart';
import 'perf_pdf_reader.dart';
import 'perf_pdf_book_reader.dart';
import 'perf_recorder.dart';

import '../../tool/perf_probe/src/probe_binding.dart';
import '../../tool/perf_probe/src/probe_engine.dart';
import '../../tool/perf_probe/src/pdf_multi_window.dart';
import 'perf_pdf_multi_window.dart';
import '../../tool/perf_probe/src/probe_completion.dart';
import 'perf_framework_scheduler.dart';

/// One shared workload for the integration and native framework entrypoints.
/// The entrypoint owns test reporting; this session owns fixture/workload cleanup.
class PerfResourceProbeSession {
  PerfResourceProbeSession({required this.run, required this.complete});

  final Future<void> Function(WidgetController controller) run;
  final Future<void> Function({
    required bool passed,
    List<String> testFailures,
  })
  complete;
}

PerfResourceProbeSession createPerfResourceProbeSession(
  WidgetsBinding binding, {
  required PerfBindingMode bindingMode,
}) {
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
  final scenarioSet = perfOption(
    'PERF_SCENARIO_SET',
    const String.fromEnvironment('PERF_SCENARIO_SET', defaultValue: 'all'),
  );
  final pdfCasePath = perfOption(
    'PERF_PDF_CASE',
    const String.fromEnvironment('PERF_PDF_CASE'),
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

  Future<void> complete({
    required bool passed,
    List<String> testFailures = const [],
  }) async {
    await recorderDone.future;
    if (!canWriteOutput) return;
    await writePerfProbeCompletion(
      output: output,
      launchIndex: launchIndex,
      bindingMode: bindingMode,
      successful: passed && runError == null,
      error: runError?.toString(),
      fixtureId: fixtureId,
      preparationOnly: preparationOnly,
      testFailures: testFailures,
    );
  }

  Future<void> run(WidgetController tester) async {
    try {
      verifyPerfProbeBinding(binding, bindingMode);
      bindingMode.validateScenario(scenarioSet);
      final engineIdentity = parsePerfEngineIdentity(
        perfOption(
          'PERF_ENGINE_IDENTITY',
          const String.fromEnvironment('PERF_ENGINE_IDENTITY'),
        ),
        buildMode: perfBuildMode,
        platform: Platform.operatingSystem,
      );
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
          !const {
            'all',
            'pdf-reader',
            'pdf-book-view',
            'pdf-multi-window',
          }.contains(scenarioSet) ||
          warmup < 0 ||
          warmup > 10 ||
          repetitions < 1 ||
          repetitions > 100) {
        throw ArgumentError(
          'Invalid cache state, scenario set, warmup (0..10), or repetitions (1..100).',
        );
      }
      await output.create(recursive: true);
      final journal = File(p.join(output.path, 'phases.jsonl'));
      if (await journal.exists() ||
          await File(p.join(output.path, 'completion.json')).exists()) {
        throw StateError('The output directory already contains a run.');
      }
      canWriteOutput = true;
      final fixture = PerfFixture(
        Directory(dataPath),
        pdfReaderCase: await PerfPdfCase.load(pdfCasePath),
      );
      if ((scenarioSet == 'all' || scenarioSet == 'pdf-book-view') &&
          fixture.pdfReaderCase.pageCount < 5) {
        throw ArgumentError(
          'The book-view scenario needs at least five PDF pages.',
        );
      }
      if (scenarioSet == 'pdf-multi-window' &&
          (fixture.pdfReaderCase.sourceKind != PerfPdfSourceKind.generated ||
              fixture.pdfReaderCase.pageCount < 4)) {
        throw ArgumentError(
          'Multi-window QA requires a generated PDF with at least four pages.',
        );
      }
      await fixture.prepare(preparationOnly: preparationOnly);
      fixtureId = fixture.id;
      final rec = recorder = PerfRecorder(
        journal,
        binding,
        launchIndex: launchIndex,
      );
      rec.imageBudget = () => capturePdfImageBudget(pdfSharedImageBudget);
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
        'fixturePdf': {
          'pages': fixture.pdfReaderCase.pageCount,
          'mixedPageSizes': fixture.pdfReaderCase.mixedPageSizes,
          'source': fixture.pdfReaderCase.sourceKind.name,
          'sha256': fixture.pdfSha256,
        },
        'scenarioSet': scenarioSet,
        'bindingMode': bindingMode.name,
        'probeTarget': bindingMode.target,
        'limitations': [
          'Cold means a fresh app data directory; OS filesystem caches are not evicted.',
          'Startup begins at Dart main; native engine/process initialization is separate.',
          'Condition polling resolution is 16 ms; frames use engine timestamps.',
          'Heap samples are outside action latency, without forced garbage collection.',
          'Private bytes are not native-only memory; RSS minus Dart heap is not computed.',
          'PDF controller_ready is document/layout readiness, not a painted page.',
          'PDF final_image_ready is the final image for the current view recorded into the layer tree, not GPU presentation.',
          'PDF image budget bytes are caller estimates shared by views in this Dart isolate, not per-window attribution or native/GPU allocation measurements.',
          'PDF budget peak is since budget construction, including warmup and earlier phases; it is never reset.',
          ...bindingMode.limitations,
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
        verifyPerfProbeBinding(binding, bindingMode);
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
            // app.main yields before the ordinary binding attaches its root.
            return binding.rootElement != null &&
                find.byType(App).evaluate().isNotEmpty &&
                StartupTimeline.instance.toJson()['revealMs'] != null;
          },
          'usable app window',
          timeout: const Duration(minutes: 3),
        );
        final context = tester.element(find.byType(App));
        final library = await DataRepository.instance.library;
        scenario = _Scenario(tester, context, rec, library, fixture, output);
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
      final view = View.of(scenario.context);
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
          ...bindingMode.toComparisonJson(),
          'engineBinary': ?engineIdentity,
          if (scenarioSet == 'pdf-multi-window')
            'pdfMultiWindowProtocol': perfPdfMultiWindowProtocol,
          'resourceObservationVersion': perfResourceObservationVersion,
          'pdfImageBudgetMaximumBytes': pdfSharedImageBudget.maximumBytes,
          'pdfPostCloseIdleMs': perfPdfPostCloseIdle.inMilliseconds,
          'searchQuery': perfQuery,
          'searchMode': 'exact',
          'searchResultLimit': 100,
          'searchGrouping': 'none',
          'pdfLayout': scenarioSet == 'pdf-book-view'
              ? 'bookView'
              : scenarioSet == 'all'
              ? 'regularView,bookView'
              : 'regularView',
          'pdfPageCount': fixture.pdfReaderCase.pageCount,
          'pdfReaderCase': fixture.pdfReaderCase.toComparisonJson(),
          'scenarioSet': scenarioSet,
          if (scenarioSet == 'all' || scenarioSet == 'pdf-book-view')
            'pdfBookViewProtocol': {
              'version': 1,
              'layout': 'bookView',
              'rapidTurnStartPage': 2,
              'rapidTurnPairs': 3,
              'reverseDelayMs': 20,
              'input': 'applicationTurnButtonHandlers',
              'finalImage': 'liveViewerAfterTransitionLayersRemoved',
              'thumbnails': 'firstDecodedVisibleImage',
            },
        },
      });
      rec.counters = scenario.counters;
      await rec.heap.connect();
      await scenario.closeTabs();
      if (bindingMode == PerfBindingMode.framework) {
        rec.write({
          'type': 'note',
          'name': 'framework.scheduler_contract',
          'frameworkScheduler': await verifyDeferredFrameworkFrame(binding),
        });
      }
      if (scenarioSet == 'all') {
        await rec.phase(
          'index.fixture_prepare',
          scenario.indexFixture,
          warmup: true,
        );
        await scenario.installPlugin();
      }
      for (var round = 0; round < warmup + repetitions; round++) {
        scenario.iteration = round < warmup ? round : round - warmup;
        scenario.warmup = round < warmup;
        await scenario.run(scenarioSet: scenarioSet);
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
      if (scenarioSet != 'pdf-multi-window') {
        rec.skip(
          'windows.native_open_close',
          bindingMode == PerfBindingMode.integration
              ? 'installWindowingOwner rejects TestPlatformDispatcher (hasRealPlatformDispatcher=false). Its synthetic engineId is not a native pointer; real-app diagnostics are required.'
              : 'This PDF workload observes one native application window; native window open/close is a separate scenario.',
        );
      }
      rec.skip(
        'queues.depth',
        'The application exposes active work and indexing state, not complete queue depths.',
      );
      rec.skip(
        switch (scenarioSet) {
          'pdf-book-view' => 'pdf.book_view.first_preview_image',
          'pdf-multi-window' => 'pdf.multi_window.first_preview_image',
          _ => 'pdf.reader.first_preview_image',
        },
        'pdfrx 2.13.1 exposes final visible-image readiness, not the first painted preview. Controller readiness and page paint callbacks can precede any image; screenshot readback is not added to this workload.',
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
  }

  return PerfResourceProbeSession(run: run, complete: complete);
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
  _Scenario(
    this.tester,
    this.context,
    this.rec,
    this.library,
    this.fixture,
    this.output,
  );
  final WidgetController tester;
  final BuildContext context;
  final PerfRecorder rec;
  final Library library;
  final PerfFixture fixture;
  final Directory output;
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
    Duration? observationWindow,
  }) => rec.phase(
    name,
    action,
    warmup: warmup,
    iteration: iteration,
    details: details,
    observationWindow: observationWindow,
  );

  Future<void> run({required String scenarioSet}) async {
    if (scenarioSet == 'pdf-multi-window') {
      await runPerfPdfMultiWindow(
        controller: tester,
        context: context,
        fixture: fixture,
        output: output,
        phase: phase,
      );
      return;
    }
    if (scenarioSet == 'pdf-book-view') {
      await _pdfBookView();
      await _observePdfAfterClose(prefix: 'pdf.book_view');
      return;
    }
    if (scenarioSet == 'pdf-reader') {
      await _pdfReader();
      await _observePdfAfterClose();
      return;
    }
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
    await _pdfReader();
    await _observePdfAfterClose();
    await _pdfBookView();
    await _observePdfAfterClose(prefix: 'pdf.book_view');
    await phase('lifecycle.tabs_cycle', () async {
      await openText(perfBooks.keys.first);
      await openText(perfBooks.keys.last);
      tabs.add(const SetCurrentTab(0));
      await tester.pump();
      await closeTabs();
    });
    await phase(
      'lifecycle.idle_after_close',
      () => waitForPerfObservation(const Duration(seconds: 1)),
      observationWindow: const Duration(seconds: 1),
    );
  }

  Future<void> _observePdfAfterClose({String prefix = 'pdf.reader'}) => phase(
    '$prefix.idle_after_close',
    () async {
      if (tabs.state.tabs.isNotEmpty) {
        throw StateError('PDF idle observation requires closed tabs.');
      }
      await waitForPerfObservation(perfPdfPostCloseIdle);
      if (tabs.state.tabs.isNotEmpty) {
        throw StateError('A tab opened during the PDF idle observation.');
      }
    },
    observationWindow: perfPdfPostCloseIdle,
  );

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
          PdfBookTab() => !tab.pdfViewerController.isReady,
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
        // Profile builds strip debugName, which the default physical-key lookup needs.
        await tester.sendKeyEvent(
          LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
        );
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

  PdfBookBloc? _pdfBloc(PdfBookTab tab) {
    final screen = find.byWidgetPredicate(
      (widget) => widget is PdfBookScreen && identical(widget.tab, tab),
    );
    final builders = find.descendant(
      of: screen,
      matching: find.byType(BlocBuilder<PdfBookBloc, PdfBookState>),
    );
    if (builders.evaluate().isEmpty) return null;
    return tester.element(builders.first).read<PdfBookBloc>();
  }

  Finder _pdfScreen(PdfBookTab tab) => find.byWidgetPredicate(
    (widget) => widget is PdfBookScreen && identical(widget.tab, tab),
  );

  PdfBookRenderObservation? _bookObservation(PdfBookTab tab) {
    final elements = _pdfScreen(tab).evaluate();
    return elements.length == 1
        ? PdfBookScreen.renderObservationOf(elements.single)
        : null;
  }

  /// The pane stays mounted while hidden. A decoded image counts only when its
  /// render box intersects the open pane and the application viewport.
  bool _hasVisibleThumbnail(PdfBookTab tab) {
    final panes = find.descendant(
      of: _pdfScreen(tab),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ThumbnailsView &&
            identical(widget.controller, tab.pdfViewerController) &&
            widget.isPaneOpen,
      ),
    );
    if (panes.evaluate().length != 1) return false;
    final paneBox = tester.renderObject<RenderBox>(panes);
    if (!paneBox.attached || !paneBox.hasSize) return false;
    final view = View.of(tester.element(panes));
    final viewport = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final paneRect = (paneBox.localToGlobal(Offset.zero) & paneBox.size)
        .intersect(viewport);
    if (paneRect.isEmpty) return false;
    final images = find.descendant(
      of: panes,
      matching: find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null,
      ),
    );
    return images.evaluate().any((element) {
      final box = element.findRenderObject();
      return box is RenderBox &&
          box.attached &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).overlaps(paneRect);
    });
  }

  Future<void> _pdfBookView() async {
    final settings = context.read<SettingsBloc>();
    final previous = settings.state.pdfBookViewByDefault;
    Future<void> setBookView(bool enabled) async {
      settings.add(UpdatePdfBookViewByDefault(enabled));
      await _wait(
        () =>
            settings.state.pdfBookViewByDefault == enabled &&
            Settings.getValue<bool>(
                  SettingsRepository.keyPdfBookViewByDefault,
                ) ==
                enabled,
        'persisted PDF book-view preference ($enabled)',
      );
    }

    try {
      // The screen and its bloc resolve savedLayoutMode against the persisted
      // global preference. Select the real app mode before timing its opening.
      await setBookView(true);
      await _measurePdfBookView();
    } finally {
      try {
        await closeTabs();
      } finally {
        await setBookView(previous);
      }
    }
  }

  Future<void> _measurePdfBookView() async {
    final pdfCase = fixture.pdfReaderCase;
    final targets = pdfCase.navigationTargets;
    // The fixed reversal starts on spread 2–3 and turns to 4–5. Smaller cases
    // are still supported by the regular reader scenario.
    if (pdfCase.pageCount < 5) {
      throw StateError('The book-view scenario needs at least five PDF pages.');
    }
    final tab = PdfBookTab(
      book: PdfBook(title: perfPdfTitle, path: fixture.pdfPath),
      pageNumber: targets.initialPage,
    )..savedLayoutMode = PdfLayoutMode.bookView;
    Future<PdfBookRenderObservation> waitForBook(
      int page, {
      Duration timeout = const Duration(seconds: 45),
    }) {
      final controller = tab.pdfViewerController;
      final document = controller.isReady ? controller.document : null;
      return waitForPdfBookFinalImage(
        pageNumber: page,
        ownershipIsCurrent: () =>
            document != null &&
            identical(tabs.state.currentTab, tab) &&
            identical(tab.pdfViewerController, controller) &&
            controller.isReady &&
            identical(controller.document, document),
        observe: () => _bookObservation(tab),
        nextFrame: () => tester.pump(),
        timeout: timeout,
      );
    }

    final checkpoints = <String, double>{};
    final openDetails = <String, Object?>{
      'page': targets.initialPage,
      'layout': PdfLayoutMode.bookView.name,
      'checkpointsMs': checkpoints,
    };
    await phase('pdf.book_view.open', () async {
      await measurePdfReaderOpening(
        open: () {
          context.read<NavigationBloc>().add(NavigateToScreen(Screen.reading));
          tabs.add(AddTab(tab));
        },
        controllerReady: () {
          final state = _pdfBloc(tab)?.state;
          if (state is PdfBookError) throw StateError(state.message);
          return identical(tabs.state.currentTab, tab) &&
              state is PdfBookLoaded &&
              tab.pdfViewerController.isReady &&
              (_bookObservation(tab)?.layoutReady ?? false);
        },
        controller: () => tab.pdfViewerController,
        pageNumber: targets.initialPage,
        nextFrame: () => tester.pump(),
        checkpointsMs: checkpoints,
        waitForFinalImage: (remaining) async {
          openDetails['finalObservation'] = (await waitForBook(
            targets.initialPage,
            timeout: remaining,
          )).toJson();
        },
      );
    }, details: openDetails);
    final bloc = _pdfBloc(tab)!;
    final controller = tab.pdfViewerController;
    pdfCase.verifyPageCount(controller.pageCount);

    final thumbnailCheckpoints = <String, double>{};
    final thumbnailDetails = <String, Object?>{
      'readiness': 'firstDecodedVisibleImageAndLiveBookImage',
      'checkpointsMs': thumbnailCheckpoints,
    };
    await phase('pdf.book_view.thumbnails_first_image', () async {
      final elapsed = Stopwatch()..start();
      bloc.add(const pdf_events.ToggleLeftPane(true));
      final headers = find.descendant(
        of: _pdfScreen(tab),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is NavPanelTabHeader &&
              widget.tabs.any((tab) => tab.label == 'דפים'),
        ),
      );
      await _wait(
        () => headers.evaluate().length == 1,
        'PDF navigation header',
      );
      final header = tester.widget<NavPanelTabHeader>(headers);
      header.controller.animateTo(
        header.tabs.indexWhere((tab) => tab.label == 'דפים'),
        duration: Duration.zero,
      );
      await tester.pump();
      await _wait(
        () => _hasVisibleThumbnail(tab),
        'first visible PDF thumbnail',
      );
      thumbnailCheckpoints['first_visible_thumbnail_observed'] =
          elapsed.elapsedMicroseconds / Duration.microsecondsPerMillisecond;
      // Opening a pushed pane also changes the reader viewport.
      await waitForBook(targets.initialPage);
    }, details: thumbnailDetails);
    final thumbnailPane = tester.widget<ThumbnailsView>(
      find.descendant(
        of: _pdfScreen(tab),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ThumbnailsView &&
              identical(widget.controller, controller) &&
              widget.isPaneOpen,
        ),
      ),
    );
    final navigate = thumbnailPane.onNavigateToPage;
    if (navigate == null) {
      throw StateError(
        'PDF thumbnail pane has no application navigation handler',
      );
    }
    for (final (direction, page) in [
      ('forward', targets.forwardPage),
      ('backward', targets.backwardPage),
    ]) {
      final details = <String, Object?>{
        'page': page,
        'input': 'applicationThumbnailNavigationHandler',
      };
      await phase('pdf.book_view.jump_$direction', () async {
        await navigate(page).timeout(const Duration(seconds: 45));
        details['finalObservation'] = (await waitForBook(page)).toJson();
      }, details: details);
    }
    await phase('pdf.book_view.prepare_reversals', () async {
      await navigate(2).timeout(const Duration(seconds: 45));
      await waitForBook(2);
    }, details: {'page': 2});
    VoidCallback turnHandler(String tooltip) => tester
        .widget<BookViewTurnButton>(
          find.descendant(
            of: _pdfScreen(tab),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is BookViewTurnButton && widget.tooltip == tooltip,
            ),
          ),
        )
        .onPressed;
    final next = turnHandler('הפוך דף קדימה');
    final previous = turnHandler('הפוך דף אחורה');
    final initiatedTurns = <Map<String, Object?>>[];
    final reversals = <Map<String, Object?>>[];
    await phase(
      'pdf.book_view.rapid_reversals',
      () async {
        for (var pair = 0; pair < 3; pair++) {
          next();
          final started = _bookObservation(tab);
          if (started == null ||
              !(started.pageTurnActive ||
                  started.queuedTurns > 0 ||
                  started.finalImageReadyFor(4))) {
            throw StateError('PDF forward turn did not start from spread 2–3.');
          }
          initiatedTurns.add(started.toJson());
          await Future<void>.delayed(const Duration(milliseconds: 20));
          previous();
          reversals.add((await waitForBook(2)).toJson());
        }
      },
      details: {
        'input': 'applicationTurnButtonHandlers',
        'sequence': ['next', 'previous'],
        'pairs': 3,
        'reverseDelayMs': 20,
        'waitAfterEachPair': 'liveViewerAfterTransitionLayersRemoved',
        'expectedFinalPage': 2,
        'initiatedTurns': initiatedTurns,
        'finalObservations': reversals,
      },
    );
    await phase('pdf.book_view.close', () async {
      await closeTabs();
      await _wait(() => bloc.isClosed, 'PDF book-view bloc disposed');
    });
  }

  Future<void> _pdfReader() async {
    final pdfCase = fixture.pdfReaderCase;
    final targets = pdfCase.navigationTargets;
    final tab = PdfBookTab(
      book: PdfBook(title: perfPdfTitle, path: fixture.pdfPath),
      pageNumber: targets.initialPage,
    )..savedLayoutMode = PdfLayoutMode.regularView;
    final checkpoints = <String, double>{};
    await phase('pdf.reader.open', () async {
      await measurePdfReaderOpening(
        open: () {
          context.read<NavigationBloc>().add(NavigateToScreen(Screen.reading));
          tabs.add(AddTab(tab));
        },
        controllerReady: () {
          final state = _pdfBloc(tab)?.state;
          if (state is PdfBookError) throw StateError(state.message);
          final ready =
              identical(tabs.state.currentTab, tab) &&
              state is PdfBookLoaded &&
              tab.pdfViewerController.isReady;
          if (ready) pdfCase.verifyPageCount(tab.pdfViewerController.pageCount);
          return ready;
        },
        // PdfBookScreen replaces the tab's controller when it mounts.
        controller: () => tab.pdfViewerController,
        pageNumber: targets.initialPage,
        nextFrame: () => tester.pump(),
        checkpointsMs: checkpoints,
      );
    }, details: {'page': targets.initialPage, 'checkpointsMs': checkpoints});

    final controller = tab.pdfViewerController;
    final bloc = _pdfBloc(tab)!;
    for (final jump in [
      (direction: 'forward', page: targets.forwardPage),
      (direction: 'backward', page: targets.backwardPage),
    ]) {
      await phase('pdf.reader.jump_${jump.direction}', () async {
        await controller
            .goToPage(pageNumber: jump.page, duration: Duration.zero)
            .timeout(const Duration(seconds: 45));
        await waitForPdfFinalImage(
          controller,
          pageNumber: jump.page,
          nextFrame: () => tester.pump(),
        );
      }, details: {'page': jump.page});
    }
    final zoomPage = targets.zoomPage;
    final zoomDetails = <String, Object?>{
      'page': zoomPage,
      'anchor': 'pageCenter',
      'requestedZoomFactor': targets.zoomFactor,
    };
    await phase('pdf.reader.zoom', () async {
      final zoom = controller.currentZoom;
      final targetZoom = (zoom * targets.zoomFactor).clamp(
        controller.minScale,
        controller.maxScale,
      );
      if (targetZoom - zoom <= 0.000001) {
        throw StateError('PDF reader cannot zoom in from $zoom');
      }
      zoomDetails['zoomBefore'] = zoom;
      zoomDetails['targetZoom'] = targetZoom;
      await controller
          .setZoom(
            controller.layout.pageLayouts[zoomPage - 1].center,
            targetZoom,
            duration: Duration.zero,
          )
          .timeout(const Duration(seconds: 45));
      await waitForPdfFinalImage(
        controller,
        pageNumber: zoomPage,
        nextFrame: () => tester.pump(),
        expectedZoom: targetZoom,
      );
      zoomDetails['zoomAfter'] = controller.currentZoom;
    }, details: zoomDetails);
    await phase('pdf.reader.close', () async {
      await closeTabs();
      await _wait(() => bloc.isClosed, 'PDF reader bloc disposed');
    });
  }
}

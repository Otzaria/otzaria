import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win;

import '../test/test_helpers/memory_cache_provider.dart';
import 'support/report_native_keyboard.dart';

class _HistoryCollector extends AppReportCollector {
  @override
  Future<AppReportAttachments> collect() async =>
      const AppReportAttachments(diagnostics: {}, errorLog: '');
}

win.HWND _foreground() => win.GetForegroundWindow();

void _releaseInputAndCloseHistory() => using((arena) {
  final release = [
    win.VK_LCONTROL,
    win.VK_RCONTROL,
    win.VK_LMENU,
    win.VK_RMENU,
    win.VK_LWIN,
    win.VK_RWIN,
    win.VK_V,
  ];
  final inputs = arena<win.INPUT>(release.length + 2);
  for (var i = 0; i < release.length; i++) {
    inputs[i].type = win.INPUT_KEYBOARD;
    inputs[i].ki.wVk = release[i];
    inputs[i].ki.dwFlags = win.KEYEVENTF_KEYUP;
  }
  for (var i = 0; i < 2; i++) {
    final input = inputs[release.length + i];
    input.type = win.INPUT_KEYBOARD;
    input.ki.wVk = win.VK_ESCAPE;
    input.ki.dwFlags = win.KEYBD_EVENT_FLAGS(
      i == 0 ? 0 : win.KEYEVENTF_KEYUP,
    );
  }
  win.SendInput(release.length + 2, inputs, sizeOf<win.INPUT>());
});

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final results = <Map<String, Object?>>[];
  final output = Directory(Platform.environment['REPORT_QA_HISTORY_OUTPUT']!);
  const json = JsonEncoder.withIndent('  ');
  final reportedFailures = <Map<String, Object?>>[];
  final originalExceptionReporter = reportTestException;
  reportTestException = (details, testDescription) {
    reportedFailures.add({
      'methodName': testDescription,
      'exceptionType': details.exception.runtimeType.toString(),
      'exceptionMessage': details.exceptionAsString(),
      'details': details.toString(),
    });
    originalExceptionReporter(details, testDescription);
  };

  tearDownAll(() async {
    await output.create(recursive: true);
    await File(p.join(output.path, 'flutter-summary.json')).writeAsString(
      json.convert({
        'renderer': 'Real Flutter Windows AppReportDialog',
        'sourceHead': Platform.environment['REPORT_QA_SOURCE_HEAD'],
        'qaHead': Platform.environment['REPORT_QA_QA_HEAD'],
        'baselineHead': Platform.environment['REPORT_QA_BASELINE_HEAD'],
        'baselineRun': Platform.environment['REPORT_QA_BASELINE_RUN'],
        'nativeTraceEnabled':
            Platform.environment['REPORT_QA_HISTORY_TRACE']?.isNotEmpty ??
            false,
        'osVersion': Platform.operatingSystemVersion,
        'allTestsPassed': binding.failureMethodsDetails.isEmpty,
        'failedTests': [
          for (final failure in binding.failureMethodsDetails)
            failure.methodName,
        ],
        'failureDetails': [
          for (final failure in binding.failureMethodsDetails)
            {'methodName': failure.methodName, 'details': failure.details},
        ],
        'reportedFailureDetails': reportedFailures,
        'cases': results,
      }),
    );
  });

  // Controls do not open history. Text history learns the image row structure.
  for (final mode in ['plain-v', 'alt-v', 'posted-v', 'text', 'image']) {
    final negativeControl = mode.endsWith('-v');
    final imagePayload = mode == 'image';
    for (final textFocus in negativeControl ? [true] : [true, false]) {
      final name = '$mode-${textFocus ? 'focused' : 'unfocused'}';
      testWidgets('real Windows history selection in report: $name', (
        tester,
      ) async {
        expect(Platform.isWindows, isTrue);
        final caseDir = Directory(p.join(output.path, name));
        await caseDir.create(recursive: true);
        final fixtureA = 'OTZARIA-HISTORY-QA-A-$name';
        final fixtureB = 'OTZARIA-HISTORY-QA-B-$name';
        final temporary = await Directory.systemTemp.createTemp('history_qa_');
        AppPaths.debugOverrideDataRootPath(temporary.path);
        UserStateDatabase.instance.overridePath(
          p.join(temporary.path, 'user_state.db'),
        );
        await Settings.init(cacheProvider: MemoryCacheProvider());
        await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
        await Settings.setValue<String>(
          SettingsRepository.keySettingsLanguage,
          'en',
        );
        const startingTitle = 'Title preserved: מקור ';
        final service = AppReportService();
        AppReportBloc? reportBloc;
        Process? controller;
        final events = <Map<String, Object?>>[];
        final evidence = <String, Object?>{
          'case': name,
          'startedAt': DateTime.now().toUtc().toIso8601String(),
          'payload': imagePayload ? 'image' : 'text',
          'negativeControl': negativeControl,
          'textFieldFocus': textFocus,
          'historySelectionVerified': false,
          'reportAssertionsPassed': false,
        };
        results.add(evidence);
        bool observe(KeyEvent event) {
          events.add({
            'utc': DateTime.now().toUtc().toIso8601String(),
            'type': event.runtimeType.toString(),
            'physical': '0x${event.physicalKey.usbHidUsage.toRadixString(16)}',
            'logical': '0x${event.logicalKey.keyId.toRadixString(16)}',
            'logicalName': event.logicalKey.debugName,
            'character': event.character,
            'synthesized': event.synthesized,
            'controlPressed': HardwareKeyboard.instance.isControlPressed,
            'foreground': _foreground().address,
            'focusLabel': FocusManager.instance.primaryFocus?.debugLabel,
          });
          return false;
        }

        HardwareKeyboard.instance.addHandler(observe);
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await focusNativeReportWindow(tester);
          await const MethodChannel(
            'otzaria/splash',
          ).invokeMethod<void>('close');
          await pumpNativeUntil(tester, () {
            final viewport =
                tester.view.physicalSize / tester.view.devicePixelRatio;
            return viewport.width >= 900 && viewport.height >= 600;
          }, reason: 'The actual Flutter desktop viewport must be ready.');
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showAppReportDialog(
                      context,
                      createBloc: () => reportBloc = AppReportBloc(
                        trigger: AppReportTrigger.manual,
                        service: service,
                        collector: _HistoryCollector(),
                        redactor: AppReportRedactor(environment: const {}),
                        initialTitle: startingTitle,
                        appVersion: 'windows-history-qa',
                      ),
                    ),
                    child: const Text('Open actual report'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open actual report'));
          await pumpNativeUntil(
            tester,
            () => reportBloc?.state is AppReportEditing,
            reason: 'The real report form must finish loading.',
          );
          await focusNativeReportWindow(tester);
          final bloc = reportBloc!;
          final title = find.byKey(const ValueKey('app-report-title'));
          final editor = tester.widget<EditableText>(
            find.descendant(of: title, matching: find.byType(EditableText)),
          );
          editor.controller.selection = TextSelection.collapsed(
            offset: editor.controller.text.length,
          );
          if (textFocus) {
            await tester.ensureVisible(title);
            editor.focusNode.requestFocus();
          } else {
            FocusManager.instance.primaryFocus?.unfocus();
          }
          await tester.pump();
          expect(editor.focusNode.hasFocus, textFocus);
          evidence['before'] = {
            'title': editor.controller.text,
            'imageCount': (bloc.state as AppReportEditing).images.length,
            'focused': editor.focusNode.hasFocus,
          };
          evidence['flutterWindow'] = _foreground().address;
          await File(p.join(caseDir.path, 'case.json')).writeAsString(
            json.convert({
              'processId': pid,
              'window': _foreground().address,
              'payload': imagePayload ? 'image' : 'text',
              'mode': mode,
              'fixtureA': fixtureA,
              'fixtureB': fixtureB,
              'imageA': [textFocus ? 220 : 221, 20, 60],
              'imageB': [textFocus ? 30 : 31, 144, 255],
            }),
          );
          controller = await Process.start('powershell.exe', [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-MTA',
            '-File',
            Platform.environment['REPORT_QA_HISTORY_CONTROLLER']!,
            '-Root',
            caseDir.path,
          ]);
          final stdout = StringBuffer();
          final stderr = StringBuffer();
          final stdoutDone = controller.stdout
              .transform(utf8.decoder)
              .forEach(stdout.write);
          final stderrDone = controller.stderr
              .transform(utf8.decoder)
              .forEach(stderr.write);
          int? exitCode;
          unawaited(controller.exitCode.then((value) => exitCode = value));
          final deadline = DateTime.now().add(const Duration(seconds: 85));
          while (exitCode == null && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            await tester.pump(const Duration(milliseconds: 25));
          }
          if (exitCode == null) {
            controller.kill();
            evidence['controllerTimedOut'] = true;
          }
          await Future.wait([
            stdoutDone,
            stderrDone,
          ]).timeout(const Duration(seconds: 5));
          await File(
            p.join(caseDir.path, 'controller.stdout.log'),
          ).writeAsString(stdout.toString());
          await File(
            p.join(caseDir.path, 'controller.stderr.log'),
          ).writeAsString(stderr.toString());
          evidence['controllerExitCode'] = exitCode;
          final resultFile = File(p.join(caseDir.path, 'result.json'));
          final controllerResult = await resultFile.exists()
              ? jsonDecode(await resultFile.readAsString())
                    as Map<String, dynamic>
              : <String, dynamic>{'outcome': 'no-controller-result'};
          evidence['controller'] = controllerResult;
          evidence['historySelectionVerified'] =
              controllerResult['historySelectionVerified'] == true;
          expect(evidence['controllerTimedOut'], isNot(true));
          expect(exitCode, 0);
          expect(controllerResult['probeCompleted'], isTrue);
          bool vDelivered() => events.any(
            (event) =>
                event['type'] == 'KeyDownEvent' &&
                event['logical'] == '0x76' &&
                event['synthesized'] == false,
          );
          void expectInputReleased() {
            expect(_foreground().address, evidence['flutterWindow']);
            for (final key in [
              win.VK_CONTROL,
              win.VK_MENU,
              win.VK_LWIN,
              win.VK_V,
            ]) {
              expect(win.GetAsyncKeyState(key) & 0x8000, 0);
            }
            expect(HardwareKeyboard.instance.isControlPressed, isFalse);
            expect(HardwareKeyboard.instance.isAltPressed, isFalse);
            expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
            expect(
              HardwareKeyboard.instance.logicalKeysPressed.contains(
                LogicalKeyboardKey.keyV,
              ),
              isFalse,
            );
          }

          if (negativeControl) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await tester.pump();
            expect(controllerResult['nativeControlInputSent'], isTrue);
            expect(
              vDelivered(),
              isTrue,
              reason:
                  'A negative control must deliver an actual V event to Flutter.',
            );
            expect(editor.controller.text.contains(fixtureA), isFalse);
            expect(
              editor.controller.text.contains(fixtureB),
              isFalse,
              reason:
                  'Typing virtual V without Ctrl must not paste clipboard data.',
            );
            expect((bloc.state as AppReportEditing).images, isEmpty);
            evidence['unmappedVObserved'] = events.any(
              (event) =>
                  event['type'] == 'KeyDownEvent' &&
                  event['logical'] == '0x76' &&
                  event['physical'] == '0x1600000000' &&
                  event['synthesized'] == false,
            );
            expect(tester.takeException(), isNull);
            expectInputReleased();
            evidence['reportAssertionsPassed'] = true;
            return;
          }
          expect(
            controllerResult['historySelectionVerified'],
            isTrue,
            reason:
                'Real Windows history selection is a prerequisite, not a simulated paste: ${controllerResult['outcome']}',
          );
          final expectedTitle = textFocus && !imagePayload
              ? '$startingTitle$fixtureA'
              : startingTitle;
          await pumpNativeUntil(
            tester,
            () => imagePayload
                ? (bloc.state as AppReportEditing).images.isNotEmpty
                : (!textFocus || editor.controller.text == expectedTitle),
            reason:
                'The actual Windows history choice must reach the production report handler.',
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await tester.pump();
          expect(
            editor.controller.text,
            expectedTitle,
            reason: 'Text must be inserted exactly once.',
          );
          expect((bloc.state as AppReportEditing).title, expectedTitle);
          final images = (bloc.state as AppReportEditing).images;
          if (imagePayload) {
            expect(
              images,
              hasLength(1),
              reason: 'Exactly one history image must be attached.',
            );
            final codec = await ui.instantiateImageCodec(images.single.bytes);
            final frame = await codec.getNextFrame();
            try {
              expect(frame.image.width, 4);
              expect(frame.image.height, 4);
              final pixels = await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              expect(
                pixels!.buffer.asUint8List(),
                List<int>.generate(
                  64,
                  (i) => [textFocus ? 220 : 221, 20, 60, 255][i % 4],
                ),
                reason:
                    'The old red bitmap A must be attached, not the current blue bitmap B.',
              );
            } finally {
              frame.image.dispose();
              codec.dispose();
            }
          } else {
            expect(images, isEmpty);
            expect(
              (await Clipboard.getData(Clipboard.kTextPlain))?.text,
              fixtureA,
            );
          }
          evidence['vKeyDownDelivered'] = vDelivered();
          expectInputReleased();
          expect(editor.focusNode.hasFocus, textFocus);
          expect(tester.takeException(), isNull);
          evidence['reportAssertionsPassed'] = true;
        } finally {
          HardwareKeyboard.instance.removeHandler(observe);
          controller?.kill();
          evidence['finishedAt'] = DateTime.now().toUtc().toIso8601String();
          evidence['keyEvents'] = events;
          evidence['inputBeforeCleanup'] = {
            'foreground': _foreground().address,
            'nativeControl': win.GetAsyncKeyState(win.VK_CONTROL) & 0x8000 != 0,
            'nativeAlt': win.GetAsyncKeyState(win.VK_MENU) & 0x8000 != 0,
            'nativeWin': win.GetAsyncKeyState(win.VK_LWIN) & 0x8000 != 0,
            'nativeV': win.GetAsyncKeyState(win.VK_V) & 0x8000 != 0,
            'flutterKeys': [
              for (final key in HardwareKeyboard.instance.logicalKeysPressed)
                '0x${key.keyId.toRadixString(16)}',
            ],
          };
          final state = reportBloc?.state;
          evidence['after'] = state is AppReportEditing
              ? {
                  'title': state.title,
                  'imageCount': state.images.length,
                  'imageBytes': [
                    for (final image in state.images) image.bytes.length,
                  ],
                }
              : {'state': state.runtimeType.toString()};
          await File(
            p.join(caseDir.path, 'flutter.json'),
          ).writeAsString(json.convert(evidence));
          _releaseInputAndCloseHistory();
          final closed = reportBloc?.stream.drain<void>();
          await tester.pumpWidget(const SizedBox.shrink());
          if (closed != null) {
            await closed.timeout(const Duration(seconds: 10));
          }
          await service.deleteDraft();
          await AppReportService.suspendAutomaticFlush();
          UiSnack.hide();
          UserStateDatabase.instance.close();
          AppPaths.debugOverrideDataRootPath(null);
          await temporary.delete(recursive: true);
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  }
}

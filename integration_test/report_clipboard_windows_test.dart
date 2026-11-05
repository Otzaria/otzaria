import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_image_sources.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';

import '../test/test_helpers/memory_cache_provider.dart';
import 'support/report_native_keyboard.dart';

class _KeyboardReportCollector extends AppReportCollector {
  @override
  Future<AppReportAttachments> collect() async =>
      const AppReportAttachments(diagnostics: {}, errorLog: '');
}

// Runs inside the native Windows application with the real clipboard plugin
// and SendInput keyboard events. Win+V clipboard-history UI remains untested.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const sources = AppReportImageSources();
  late SystemClipboard clipboard;
  final passed = <String>[];
  final nativeKeyboardPaths = <Map<String, Object?>>[];
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOwSdnyHwAEiAJU2GM8WwAAAABJRU5ErkJggg==',
  );
  final gif = base64Decode(
    'R0lGODlhAgACAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACwAAAAAAgACAAAIBgABCAQQEAAh+QQBCgABACwAAAAAAgACAIEAAP8AAAAAAAAAAAAIBgABCAQQEAA7',
  );

  setUpAll(() {
    expect(
      Platform.isWindows,
      isTrue,
      reason: 'Run this integration test with -d windows.',
    );
    final native = SystemClipboard.instance;
    expect(
      native,
      isNotNull,
      reason: 'The actual registered Windows clipboard plugin is required.',
    );
    clipboard = native!;
  });

  tearDownAll(() async {
    await Clipboard.setData(const ClipboardData(text: ''));
    final evidence = <String, Object?>{
      'renderer': 'Native Flutter Windows integration test',
      'hostPlatform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'provider': 'Registered super_clipboard Windows plugin',
      'commit': Platform.environment['REPORT_QA_COMMIT'],
      'reviewedHead': Platform.environment['REPORT_QA_REVIEWED_HEAD'],
      // Completed assertions alone do not mean the test passed: Flutter can
      // report a layout failure after the test body returns.
      'completedChecks': passed,
      'allTestsPassed': binding.failureMethodsDetails.isEmpty,
      'failedTests': [
        for (final failure in binding.failureMethodsDetails) failure.methodName,
      ],
      'nativeClipboard': true,
      'nativeKeyboardInput': nativeKeyboardPaths.isNotEmpty,
      'nativeKeyboardPaths': nativeKeyboardPaths,
      'windowsClipboardHistoryUi': false,
    };
    binding.reportData = evidence;
    final file = File(
      Platform.environment['REPORT_QA_NATIVE_OUTPUT'] ??
          'build/reporting_qa/native-clipboard.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(evidence),
    );
  });

  testWidgets(
    'native Flutter text is readable by the reporting clipboard provider',
    (tester) async {
      const text = 'טקסט רגיל בעברית + English 😀';
      await Clipboard.setData(const ClipboardData(text: text));
      final reader = await clipboard.read();
      expect(await reader.readValue(Formats.plainText), text);
      expect(await sources.readClipboard(skipIfText: true), isEmpty);
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
      passed.add('Flutter text -> native provider -> unchanged Flutter text');
    },
  );

  testWidgets('native PNG reaches the production report source unchanged', (
    tester,
  ) async {
    final item = DataWriterItem(suggestedName: 'native.png')
      ..add(Formats.png(png));
    await clipboard.write([item]);
    for (final skipIfText in [false, true]) {
      final images = await sources.readClipboard(skipIfText: skipIfText);
      expect(images, hasLength(1));
      expect(images.single.mimeType, 'image/png');
      expect(images.single.bytes, png);
    }
    passed.add('Native PNG -> production source, both text-precedence modes');
  });

  testWidgets(
    'native two-frame GIF wins over PNG without losing animation bytes',
    (tester) async {
      final item = DataWriterItem(suggestedName: 'animated.gif')
        ..add(Formats.gif(gif))
        ..add(Formats.png(png));
      await clipboard.write([item]);
      final images = await sources.readClipboard();
      expect(images, hasLength(1));
      expect(images.single.mimeType, 'image/gif');
      expect(images.single.bytes, gif);
      final codec = await ui.instantiateImageCodec(images.single.bytes);
      try {
        expect(codec.frameCount, 2);
      } finally {
        codec.dispose();
      }
      passed.add('Native GIF + PNG -> exact GIF bytes with two decoded frames');
    },
  );

  testWidgets('native mixed text and PNG preserves ordinary text precedence', (
    tester,
  ) async {
    const text = 'טקסט להדבקה רגילה';
    final item = DataWriterItem()
      ..add(Formats.png(png))
      ..add(Formats.plainText(text));
    await clipboard.write([item]);
    expect(await sources.readClipboard(skipIfText: true), isEmpty);
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
    final explicit = await sources.readClipboard();
    expect(explicit.single.bytes, png);
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
    passed.add(
      'Native text + PNG -> ordinary text precedence without changing clipboard',
    );
  });

  testWidgets('native advertised empty text does not hide its PNG', (
    tester,
  ) async {
    final item = DataWriterItem()
      ..add(Formats.png(png))
      ..add(Formats.plainText(''));
    await clipboard.write([item]);
    final reader = await clipboard.read();
    expect(reader.canProvide(Formats.plainText), isTrue);
    final images = await sources.readClipboard(skipIfText: true);
    expect(images, hasLength(1));
    expect(images.single.bytes, png);
    passed.add(
      'Native empty text + PNG -> production image source retains PNG',
    );
  });

  for (final shiftInsert in [false, true]) {
    final shortcut = shiftInsert ? 'Shift+Insert' : 'Ctrl+V';
    for (final textFocus in [false, true]) {
      // Separate forms keep the text-only asynchronous clipboard read from
      // overlapping a subsequent clipboard write for the PNG case.
      for (final imagePayload in [false, true]) {
        final payload = imagePayload ? 'PNG' : 'text';
        testWidgets(
          'OS $shortcut pastes $payload in AppReportDialog; text focus=$textFocus',
          (tester) async {
            final temporary = await Directory.systemTemp.createTemp(
              'otzaria_native_report_keys_',
            );
            AppPaths.debugOverrideDataRootPath(temporary.path);
            UserStateDatabase.instance.overridePath(
              p.join(temporary.path, 'user_state.db'),
            );
            await Settings.init(cacheProvider: MemoryCacheProvider());
            await Settings.setValue<bool>(
              SettingsRepository.keyOfflineMode,
              true,
            );
            await Settings.setValue<String>(
              SettingsRepository.keySettingsLanguage,
              'en',
            );
            const startingTitle = 'Title preserved: מקור ';
            const text = 'Native paste: טקסט רגיל 😀';
            final expectedTitle = textFocus && !imagePayload
                ? '$startingTitle$text'
                : startingTitle;
            final service = AppReportService();
            AppReportBloc? reportBloc;
            try {
              // main() normally expands the hidden 240x240 startup window.
              // Prepare the actual desktop viewport before laying out a form.
              await tester.pumpWidget(const SizedBox.shrink());
              await focusNativeReportWindow(tester);
              await pumpNativeUntil(
                tester,
                () {
                  final viewport =
                      tester.view.physicalSize / tester.view.devicePixelRatio;
                  return viewport.width >= 900 && viewport.height >= 600;
                },
                reason:
                    'Windows must deliver the resized desktop viewport before the report opens.',
              );
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
                            collector: _KeyboardReportCollector(),
                            redactor: AppReportRedactor(environment: const {}),
                            initialTitle: startingTitle,
                            appVersion: 'native-keyboard-qa',
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
                reason:
                    'The real report form must load its draft and attachments.',
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
              expect(
                tester
                    .widgetList<EditableText>(find.byType(EditableText))
                    .any(
                      (field) => field.focusNode.hasFocus,
                    ),
                textFocus,
              );

              final item = DataWriterItem(
                suggestedName: imagePayload ? 'os-keyboard.png' : null,
              );
              if (imagePayload || textFocus) {
                item.add(Formats.png(png));
              }
              if (!imagePayload) {
                item.add(Formats.plainText(text));
              }
              await clipboard.write([item]);
              await sendNativePaste(
                tester,
                shiftInsert: shiftInsert,
                applied: () => imagePayload
                    ? (bloc.state as AppReportEditing).images.length == 1
                    : editor.controller.text == expectedTitle,
              );
              expect(editor.controller.text, expectedTitle);
              expect((bloc.state as AppReportEditing).title, expectedTitle);
              final images = (bloc.state as AppReportEditing).images;
              if (imagePayload) {
                expect(images, hasLength(1));
                expect(images.single.bytes, png);
                expect(images.single.mimeType, 'image/png');
              } else {
                expect(images, isEmpty);
                expect(
                  (await Clipboard.getData(Clipboard.kTextPlain))?.text,
                  text,
                );
              }
              expect(editor.focusNode.hasFocus, textFocus);
              expect(await service.getPendingReports(), isEmpty);
              expect(
                tester.takeException(),
                isNull,
                reason: 'The native report form must render without errors.',
              );
              nativeKeyboardPaths.add({
                'shortcut': shortcut,
                'payload': payload,
                'textFieldFocus': textFocus,
                'foregroundProcessId': pid,
                'nativeNonSynthesizedKeyDownObserved': true,
                'titlePreservedExactly': true,
                'mixedTextAndImagePreservesTextPrecedence':
                    textFocus && !imagePayload ? true : null,
                'pngBytesPreservedInRealReportBloc': imagePayload ? true : null,
                'keysReleased': true,
              });
              passed.add(
                'OS $shortcut $payload -> AppReportDialog; text focus=$textFocus',
              );
            } finally {
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
          },
          timeout: const Timeout(Duration(minutes: 1)),
        );
      }
    }
  }
}

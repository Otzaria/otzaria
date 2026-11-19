import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  test('export keeps all rows, hides private text by default (#4447)', () {
    final reports = List.generate(
      101,
      (index) => AppReport(
        reportId: 'report-$index',
        type: AppReportType.bug,
        trigger: AppReportTrigger.manual,
        title: 'Issue $index PRIVATE_TITLE',
        description: 'PRIVATE_DESCRIPTION',
        stepsToReproduce: 'PRIVATE_STEPS',
        reporterEmail: 'private@example.com',
        errorLog: 'PRIVATE_LOG',
        diagnostics: const {'secret': 'PRIVATE_DIAGNOSTICS'},
        appVersion: 'test',
        platform: 'linux',
        createdAt: DateTime.utc(2026, 11, 18),
        issueNumber: index,
      ),
    );

    final safe = serializeSentAppReportHistory(reports, includeText: false);
    final decoded = jsonDecode(safe) as Map<String, dynamic>;
    final rows = decoded['reports'] as List<dynamic>;
    expect(rows, hasLength(101));
    expect((rows.last as Map<String, dynamic>)['issueNumber'], 100);
    for (final forbidden in [
      'PRIVATE_TITLE',
      'PRIVATE_DESCRIPTION',
      'PRIVATE_STEPS',
      'private@example.com',
      'PRIVATE_LOG',
      'PRIVATE_DIAGNOSTICS',
    ]) {
      expect(safe, isNot(contains(forbidden)));
    }

    final full = serializeSentAppReportHistory(reports, includeText: true);
    expect(full, contains('PRIVATE_TITLE'));
    expect(full, contains('PRIVATE_DESCRIPTION'));
    expect(full, contains('PRIVATE_STEPS'));
    expect(full, isNot(contains('private@example.com')));
    expect(full, isNot(contains('PRIVATE_DIAGNOSTICS')));
    expect(full, isNot(contains('PRIVATE_LOG')));
  });

  for (final includeText in [false, true]) {
    testWidgets(
      'history export authenticates once (includeText: $includeText)',
      (
        tester,
      ) async {
        final names = <String>[];
        final picker = FilePickerPlatform.instance;
        final pathProvider = PathProviderPlatform.instance;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
        FilePickerPlatform.instance = _RecordingPicker(names);
        PathProviderPlatform.instance = _DownloadsProvider();
        DialogOwner.mainWindowHwnd = 1;
        if (Platform.isMacOS) {
          messenger.setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'save');
            names.add((call.arguments as Map)['fileName'] as String);
            return null;
          });
        }
        addTearDown(() {
          FilePickerPlatform.instance = picker;
          PathProviderPlatform.instance = pathProvider;
          DialogOwner.resetForTest();
          messenger.setMockMethodCallHandler(channel, null);
        });
        final bloc = _SettingsBloc();
        whenListen(
          bloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
            protectedModeEnabled: true,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: RepositoryProvider<SettingsRepository>.value(
              value: _SettingsRepository(),
              child: BlocProvider<SettingsBloc>.value(
                value: bloc,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: AppReportsPanel(
                      isOfflineMode: true,
                      crashReportMode: AppCrashReportMode.ask,
                      onCrashReportModeChanged: (_) {},
                      service: _ReportService(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('דיווחים שנשלחו'));
        await tester.pumpAndSettle();
        final export = find.text(
          includeText ? 'ייצא עם תוכן הדיווחים' : 'ייצא היסטוריה',
        );
        await tester.ensureVisible(export);
        await tester.tap(export);
        await tester.pumpAndSettle();
        if (includeText) {
          final confirm = find.text('ייצא כולל תוכן');
          expect(confirm, findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(confirm, findsOneWidget);
          expect(names, isEmpty);
          await tester.tap(find.text('ביטול'));
          await tester.pumpAndSettle();
          expect(find.byType(SaferModePasswordDialog), findsNothing);
          expect(names, isEmpty);
          await tester.tap(export);
          await tester.pumpAndSettle();
          final button = find.ancestor(
            of: confirm,
            matching: find.byType(FilledButton),
          );
          Focus.of(tester.element(confirm)).requestFocus();
          await tester.pump();
          expect(button, findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
        }
        expect(find.byType(SaferModePasswordDialog), findsOneWidget);
        await tester.enterText(find.byType(RtlTextField), '1234');
        await tester.tap(find.text('אישור'));
        await tester.pumpAndSettle();
        expect(find.byType(SaferModePasswordDialog), findsNothing);
        expect(names, [
          includeText
              ? 'otzaria-sent-reports-full.json'
              : 'otzaria-sent-reports.json',
        ]);
      },
    );
  }
}

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _SettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => true;

  @override
  bool verifyProtectedModePassword(String password) => password == '1234';
}

class _ReportService extends Fake implements AppReportService {
  @override
  Future<List<AppReport>> getPendingReports() async => [];

  @override
  Future<List<AppReport>> getSentReports() async => [
    AppReport(
      reportId: 'report-1',
      type: AppReportType.bug,
      trigger: AppReportTrigger.manual,
      title: 'Report',
      appVersion: 'test',
      platform: 'linux',
      createdAt: DateTime.utc(2026, 11, 18),
    ),
  ];

  @override
  Future<int> getSentReportsTotal() async => 1;
}

class _DownloadsProvider extends PathProviderPlatform {
  @override
  Future<String?> getDownloadsPath() async => null;
}

class _RecordingPicker extends FilePickerPlatform {
  _RecordingPicker(this.names);

  final List<String> names;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    names.add(fileName);
    return null;
  }
}

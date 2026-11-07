import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/reports/bloc/book_report_draft_cubit.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DirectErrorReportService service;
  final live = <BookReportDraftCubit>[];
  const initial = {'mode': 'freeText', 'details': '', 'proposedText': ''};
  const target = {'bookTitle': 'Frozen QA book', 'lineNumber': 7};
  const firstText = 'First deliberate report';
  const secondText = 'Newer text written in another open form';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('qa_book_delivery_');
    RunnerWindowChannel.debugSupportedOverride = false;
    AppPaths.debugOverrideDataRootPath(directory.path);
    UserStateDatabase.instance.overridePath('${directory.path}/state.db');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      'qa@example.com',
    );
    await Settings.setValue<String>(
      SettingsRepository.keySettingsLanguage,
      'he',
    );
    service = DirectErrorReportService();
  });

  tearDown(() async {
    await DirectErrorReportService.suspendAutomaticFlush();
    await service.closeHttpClient();
    await UserStateDatabase.instance.flushWrites();
    UserStateDatabase.instance.close();
    RunnerWindowChannel.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    directory.deleteSync(recursive: true);
  });

  Future<BuildContext> mount(WidgetTester tester) async {
    late BuildContext result;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              result = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return result;
  }

  Future<({BookReportDraftCubit first, BookReportDraftCubit second})>
  pair() async {
    final first = BookReportDraftCubit(
      target: target,
      initialForm: initial,
      autosaveDelay: const Duration(days: 1),
    );
    live.add(first);
    first.updateForm({...initial, 'details': firstText});
    await first.flush();
    final record = (await ReportDraftStore.instance.read(first.id))!;
    final second = BookReportDraftCubit(
      target: target,
      initialForm: initial,
      restored: record,
      autosaveDelay: const Duration(days: 1),
    );
    live.add(second);
    expect(
      second.id,
      first.id,
      reason: 'These are two real sessions of the same persisted draft.',
    );
    second.updateForm({...initial, 'details': secondText});
    await second.flush();
    return (first: first, second: second);
  }

  Future<bool> queue(
    BuildContext context,
    BookReportDraftCubit draft, {
    String? reportId,
  }) => ErrorReportHelper.handleRegularReportAction(
    context,
    ErrorReportAction.saveForLater,
    ReportedErrorData(
      selectedText: 'quoted text',
      errorDetails: draft.state.form['details'] as String,
    ),
    target['bookTitle'] as String,
    'reference 7',
    const {},
    7,
    'unchanged surrounding context',
    'qa-library',
    reportId: reportId ?? draft.reportId,
  );

  void qa(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.runAsync(() async {
          for (final draft in live) {
            if (!draft.isClosed) await draft.close();
          }
          live.clear();
        });
        UiSnack.hide();
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  qa(
    'QA old book delivery can finish without deleting a newer draft revision',
    (tester) async {
      final context = await mount(tester);
      await tester.runAsync(() async {
        final drafts = await pair();
        expect(await queue(context, drafts.first), isTrue);
        await drafts.first.complete();
        expect(drafts.first.isCompleted, isTrue);
        drafts.first.updateForm({...initial, 'details': 'late old callback'});
        await PreCloseRegistry.runAll();
        final retained = await ReportDraftStore.instance.read(drafts.second.id);
        expect(retained, isNotNull);
        expect((retained!.payload['form'] as Map)['details'], secondText);
        final pending = await service.getPendingReports();
        expect(pending, hasLength(1));
        expect(pending.single.errorDetails, firstText);
      });
    },
  );

  qa('QA both deliberate book queue actions preserve their distinct content', (
    tester,
  ) async {
    final context = await mount(tester);
    await tester.runAsync(() async {
      final drafts = await pair();
      expect(
        drafts.first.reportId,
        isNot(drafts.second.reportId),
        reason: 'New content must not reuse the previous delivery identity.',
      );
      expect(await queue(context, drafts.first), isTrue);
      await drafts.first.complete();
      expect(await queue(context, drafts.second), isTrue);
      await drafts.second.complete();

      final pending = await service.getPendingReports();
      expect(
        pending.map((report) => report.errorDetails),
        unorderedEquals([firstText, secondText]),
      );
      expect(pending.map((report) => report.id).toSet(), hasLength(2));
      expect(await ReportDraftStore.instance.list(), isEmpty);
      await PreCloseRegistry.runAll();
      expect(await ReportDraftStore.instance.list(), isEmpty);
    });
  });

  qa('QA a colliding book queue id cannot acknowledge unqueued new content', (
    tester,
  ) async {
    final context = await mount(tester);
    bool? acknowledged;
    Object? failure;
    late BookReportDraftCubit second;
    await tester.runAsync(() async {
      final drafts = await pair();
      second = drafts.second;
      expect(await queue(context, drafts.first), isTrue);
      // Force the collision independently of the UI's identity rotation.
      // Production callers must never receive a false queue acknowledgement.
      try {
        acknowledged = await queue(
          context,
          drafts.second,
          reportId: drafts.first.reportId,
        );
        if (acknowledged == true) await drafts.second.complete();
      } catch (error) {
        failure = error;
      }
    });
    await tester.pump();
    expect(
      acknowledged,
      isNot(true),
      reason: 'A queue-id collision must not finalize the unsaved newer draft.',
    );
    if (failure != null) {
      expect(failure.toString(), contains(ReportMessages.reportIdConflict));
    } else {
      expect(find.text(ReportMessages.reportIdConflict), findsOneWidget);
    }
    await tester.runAsync(() async {
      final retained = await ReportDraftStore.instance.read(second.id);
      expect(retained, isNotNull);
      expect((retained!.payload['form'] as Map)['details'], secondText);
      final pending = await service.getPendingReports();
      expect(pending, hasLength(1));
      expect(pending.single.errorDetails, firstText);
    });
  });
}

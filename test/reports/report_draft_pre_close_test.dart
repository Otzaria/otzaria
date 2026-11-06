import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/reports/bloc/book_report_draft_cubit.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import '../app_report/app_report_test_fakes.dart';
import '../test_helpers/memory_cache_provider.dart';

class _ControlledService extends FakeAppReportService {
  Completer<void>? writeGate;
  Completer<void>? deleteGate;
  final writeStarted = Completer<void>();
  final deleteStarted = Completer<void>();
  int writes = 0;
  bool failWrites = false;

  @override
  Future<void> saveDraft(AppReportDraft value) async {
    writes++;
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (failWrites) throw StateError('draft disk unavailable');
    await super.saveDraft(value);
  }

  @override
  Future<void> deleteDraft() async {
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await deleteGate?.future;
    await super.deleteDraft();
  }
}

class _ControlledStore extends ReportDraftStore {
  _ControlledStore({required this.database}) : super(database: database);
  final UserStateDatabase database;
  Completer<void>? deleteGate;
  final deleteStarted = Completer<void>();

  @override
  Future<void> delete(String id, {int? revision}) async {
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await deleteGate?.future;
    await super.delete(id, revision: revision);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => Settings.init(cacheProvider: MemoryCacheProvider()));

  Future<AppReportBloc> openApp(_ControlledService service) async {
    final bloc = AppReportBloc(
      trigger: AppReportTrigger.manual,
      service: service,
      collector: FakeAppReportCollector(),
      redactor: AppReportRedactor(environment: const {}),
      initialEmail: '',
      appVersion: 'test',
      autosaveDelay: const Duration(days: 1),
    );
    addTearDown(() async {
      if (!bloc.isClosed) await bloc.close();
    });
    bloc.add(const AppReportAttachmentsRequested());
    await bloc.stream.firstWhere((state) => state is AppReportEditing);
    return bloc;
  }

  Future<void> change(
    AppReportBloc bloc,
    AppReportEvent event,
    bool Function(AppReportEditing) match,
  ) async {
    final next = bloc.stream.firstWhere(
      (state) => state is AppReportEditing && match(state),
    );
    bloc.add(event);
    await next;
  }

  BookReportDraftCubit openBook(ReportDraftStore store) {
    final cubit = BookReportDraftCubit(
      target: const {'bookTitle': 'book', 'lineNumber': 7},
      initialForm: const {'email': '', 'details': ''},
      store: store,
      autosaveDelay: const Duration(days: 1),
    );
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    return cubit;
  }

  _ControlledStore openStore() {
    final directory = Directory.systemTemp.createTempSync('draft_pre_close_');
    final database = UserStateDatabase.openAt('${directory.path}/state.db');
    addTearDown(() {
      database.close();
      directory.deleteSync(recursive: true);
    });
    return _ControlledStore(database: database);
  }

  test('book exit persists partial text before the debounce fires', () async {
    final store = openStore();
    final cubit = openBook(store);
    cubit.updateForm(const {
      'email': 'unfinished@',
      'details': 'last keystroke',
    });
    expect(await store.list(), isEmpty);

    await PreCloseRegistry.runAll();

    final row = (await store.read(cubit.id))!;
    expect(row.payload['form'], {
      'email': 'unfinished@',
      'details': 'last keystroke',
    });
    expect(row.payload['target'], {'bookTitle': 'book', 'lineNumber': 7});
  });

  test(
    'app exit includes a field event still waiting in the event queue',
    () async {
      final service = _ControlledService();
      final bloc = await openApp(service);
      bloc.add(const AppReportDescriptionChanged('last keystroke'));

      await PreCloseRegistry.runAll();

      expect(service.draft!.description, 'last keystroke');
      expect(service.draft!.email, isEmpty);
      expect(service.sent, isEmpty);
      expect(service.queued, isEmpty);
    },
  );

  test('exit waits for an app autosave already writing to disk', () async {
    final service = _ControlledService()..writeGate = Completer<void>();
    final bloc = await openApp(service);
    await change(
      bloc,
      const AppReportDescriptionChanged('unfinished'),
      (state) => state.description == 'unfinished',
    );
    bloc.add(const AppReportAutosaveRequested(0));
    await service.writeStarted.future;
    var flushed = false;
    final pending = PreCloseRegistry.runAll().then((_) => flushed = true);
    await pumpEventQueue();
    expect(flushed, isFalse);
    service.writeGate!.complete();
    await pending;
    expect(service.draft!.description, 'unfinished');
  });

  test(
    'book exit waits for an in-flight discard without recreating its row',
    () async {
      final store = openStore()..deleteGate = Completer<void>();
      final cubit = openBook(store);
      cubit.updateForm(const {'email': '', 'details': 'unfinished'});
      await cubit.flush();
      final discard = cubit.complete();
      await store.deleteStarted.future;
      var flushed = false;
      final pending = PreCloseRegistry.runAll().then((_) => flushed = true);
      await pumpEventQueue();
      expect(flushed, isFalse);
      store.deleteGate!.complete();
      await Future.wait([discard, pending]);
      await PreCloseRegistry.runAll();
      expect(await store.read(cubit.id), isNull);
    },
  );

  for (final discard in [true, false]) {
    test(
      'app exit waits for ${discard ? 'discard' : 'delivered draft cleanup'}',
      () async {
        final service = _ControlledService()..deleteGate = Completer<void>();
        final bloc = await openApp(service);
        await change(
          bloc,
          const AppReportTitleChanged('title'),
          (s) => s.title == 'title',
        );
        await change(
          bloc,
          const AppReportDescriptionChanged('description'),
          (s) => s.description == 'description',
        );
        await change(
          bloc,
          const AppReportEmailChanged('a@b.com'),
          (s) => s.email == 'a@b.com',
        );
        final finished = bloc.stream.firstWhere(
          (state) =>
              state is AppReportEditing &&
              (discard ? state.draftDiscarded : state.isFinished),
        );
        bloc.add(
          discard
              ? const AppReportDraftDiscarded()
              : const AppReportSubmitted(),
        );
        await service.deleteStarted.future;
        var flushed = false;
        final pending = PreCloseRegistry.runAll().then((_) => flushed = true);
        await pumpEventQueue();
        expect(flushed, isFalse);
        service.deleteGate!.complete();
        await Future.wait([finished, pending]);
        await PreCloseRegistry.runAll();
        expect(service.draft, isNull);
        expect(service.sent, hasLength(discard ? 0 : 1));
      },
    );
  }

  test(
    'app exit reports persistent save failures and succeeds after recovery',
    () async {
      final service = _ControlledService()..failWrites = true;
      final bloc = await openApp(service);
      await change(
        bloc,
        const AppReportDescriptionChanged('must survive'),
        (state) => state.description == 'must survive',
      );
      await expectLater(
        PreCloseRegistry.runAll(),
        throwsA(isA<PreCloseFlushFailure>()),
      );
      expect(service.writes, 2);
      expect(service.draft, isNull);
      service.failWrites = false;
      await PreCloseRegistry.runAll();
      expect(service.draft!.description, 'must survive');
    },
  );

  test(
    'book exit reports real SQLite write failure instead of swallowing it',
    () async {
      final store = openStore();
      final cubit = openBook(store);
      final database = await store.database.database;
      database.execute('''CREATE TRIGGER reject_draft_write
      BEFORE INSERT ON report_drafts
      BEGIN SELECT RAISE(ABORT, 'disk write failed'); END''');
      cubit.updateForm(const {'email': '', 'details': 'must survive'});
      await expectLater(
        PreCloseRegistry.runAll(),
        throwsA(isA<PreCloseFlushFailure>()),
      );
      expect(cubit.state.saveFailed, isTrue);
      database.execute('DROP TRIGGER reject_draft_write');
      await PreCloseRegistry.runAll();
      expect(
        (await store.read(cubit.id))!.payload['form']['details'],
        'must survive',
      );
      expect(cubit.state.saveFailed, isFalse);
    },
  );

  test('closing the form unregisters its exit callback', () async {
    final service = _ControlledService();
    final bloc = await openApp(service);
    await change(
      bloc,
      const AppReportDescriptionChanged('saved once'),
      (state) => state.description == 'saved once',
    );
    await bloc.close();
    final writes = service.writes;
    service.failWrites = true;
    await PreCloseRegistry.runAll();
    expect(service.writes, writes);
  });
}

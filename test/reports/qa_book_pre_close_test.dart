import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/reports/bloc/book_report_draft_cubit.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';

class _ControlledStore extends ReportDraftStore {
  _ControlledStore(UserStateDatabase database) : super(database: database);

  Completer<void>? writeStarted;
  Completer<void>? allowWrite;
  Completer<void>? deleteStarted;
  Completer<void>? allowDelete;
  bool failWrites = false;
  int writeAttempts = 0;

  @override
  Future<int> write({
    required String id,
    required String kind,
    required String title,
    required Map<String, dynamic> payload,
    required int revision,
    Map<String, dynamic>? attachments,
  }) async {
    writeAttempts++;
    if (writeStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    if (allowWrite case final gate?) await gate.future;
    if (failWrites) throw const FileSystemException('QA disk full');
    return super.write(
      id: id,
      kind: kind,
      title: title,
      payload: payload,
      revision: revision,
      attachments: attachments,
    );
  }

  @override
  Future<void> delete(String id, {int? revision}) async {
    if (deleteStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    if (allowDelete case final gate?) await gate.future;
    return super.delete(id, revision: revision);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late UserStateDatabase database;
  late _ControlledStore store;
  final live = <BookReportDraftCubit>[];
  const initial = {'details': '', 'mode': 'freeText'};

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('qa_book_pre_close_');
    database = UserStateDatabase.openAt('${tmp.path}/state.db');
    store = _ControlledStore(database);
  });
  tearDown(() async {
    store.failWrites = false;
    if (store.allowWrite case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    if (store.allowDelete case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    for (final draft in live) {
      await draft.close();
    }
    live.clear();
    await database.flushWrites();
    database.close();
    tmp.deleteSync(recursive: true);
  });

  BookReportDraftCubit draft({Duration? autosaveDelay}) {
    final value = BookReportDraftCubit(
      target: const {
        'bookTitle': 'Frozen book A',
        'source': {'bookId': 12, 'lineIndex': 8, 'originalLine': '<b>אב</b>'},
      },
      initialForm: initial,
      store: store,
      // Controls the autosave clock: no timer can expire during the exit phase.
      autosaveDelay: autosaveDelay ?? const Duration(days: 1),
    );
    live.add(value);
    return value;
  }

  Future<void> exitFlush() async {
    // These are the actual app exit stages, before window destruction/exit(0).
    await PreCloseRegistry.runAll();
    await database.flushWrites();
  }

  test(
    'QA pre-close persists a new book draft before its debounce fires',
    () async {
      final current = draft();
      current.updateForm({
        ...initial,
        'details': 'last keystroke before close',
      });
      expect(await store.list(), isEmpty);
      await exitFlush();
      // Deliberately do not call Cubit.close before checking durability.
      final saved = await store.read(current.id);
      expect(
        saved,
        isNotNull,
        reason: 'Normal app shutdown must flush a live dialog before exit(0).',
      );
      expect(
        (saved!.payload['form'] as Map)['details'],
        'last keystroke before close',
      );
      expect(saved.payload['target'], current.target);
    },
  );

  test(
    'QA pre-close waits for an in-flight autosave and persists the newest edit',
    () async {
      store.writeStarted = Completer<void>();
      store.allowWrite = Completer<void>();
      final current = draft(autosaveDelay: Duration.zero);
      current.updateForm({...initial, 'details': 'older in-flight text'});
      await store.writeStarted!.future;
      current.updateForm({...initial, 'details': 'newer final text'});
      var flushed = false;
      final closing = exitFlush().then((_) => flushed = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        flushed,
        isFalse,
        reason: 'The exit flush cannot overtake disk I/O.',
      );
      store.allowWrite!.complete();
      await closing;
      expect(
        ((await store.read(current.id))!.payload['form'] as Map)['details'],
        'newer final text',
      );
    },
  );

  test(
    'QA pre-close waits for a pending explicit completion and cannot resurrect it',
    () async {
      final current = draft();
      current.updateForm({
        ...initial,
        'details': 'ready for send or explicit discard',
      });
      await current.flush();
      store.deleteStarted = Completer<void>();
      store.allowDelete = Completer<void>();
      final completing = current.complete();
      await store.deleteStarted!.future;
      current.updateForm({...initial, 'details': 'late callback'});
      var flushed = false;
      final closing = exitFlush().then((_) => flushed = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        flushed,
        isFalse,
        reason: 'A completed form must still wait for its durable deletion.',
      );
      store.allowDelete!.complete();
      await Future.wait([completing, closing]);
      await exitFlush();
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'QA pre-close exposes disk failure through the existing close registry',
    () async {
      final current = draft();
      current.updateForm({...initial, 'details': 'must not claim saved'});
      store.failWrites = true;
      await expectLater(exitFlush(), throwsA(isA<PreCloseFlushFailure>()));
      expect(
        store.writeAttempts,
        2,
        reason: 'The existing registry retries once.',
      );
      expect(current.state.saveFailed, isTrue);
      expect(current.state.form['details'], 'must not claim saved');
    },
  );
}

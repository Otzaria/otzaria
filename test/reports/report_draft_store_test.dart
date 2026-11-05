import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/reports/bloc/book_report_draft_cubit.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late UserStateDatabase database;
  late ReportDraftStore store;
  final created = DateTime.utc(2026, 11, 5);
  setUp(() {
    directory = Directory.systemTemp.createTempSync('report_draft_test_');
    database = UserStateDatabase.openAt('${directory.path}/state.db');
    store = ReportDraftStore(database: database, clock: () => created);
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });

  ReportDraftSession session(String id, {int revision = 0}) =>
      ReportDraftSession(store: store, id: id, revision: revision);
  Future<void> save(ReportDraftSession session, String text) => session.save(
    kind: ReportDraftStore.appKind,
    title: 'unfinished',
    payload: {'description': text, 'email': 'invalid email'},
  );

  test(
    'partial draft and attachments survive reopening outside transport tables',
    () async {
      final current = session('one');
      await current.save(
        kind: ReportDraftStore.appKind,
        title: 'unfinished',
        payload: {'description': '', 'email': 'not an email'},
        attachments: {
          'images': ['animated-gif-bytes'],
          'dump': 'diagnostic bytes',
        },
      );
      expect((await store.list()).single.attachments, isEmpty);
      expect((await store.read('one'))!.createdAt, created.toLocal());
      final connection = await database.database;
      expect(connection.select('SELECT * FROM pending_reports'), isEmpty);
      database.close();
      database = UserStateDatabase.openAt('${directory.path}/state.db');
      store = ReportDraftStore(database: database);
      final restored = (await store.read('one'))!;
      expect(restored.payload['email'], 'not an email');
      expect(restored.attachments['images'], ['animated-gif-bytes']);
      expect(restored.attachments['dump'], 'diagnostic bytes');
    },
  );

  test('text autosave does not rewrite unchanged heavy attachments', () async {
    final current = session('one');
    await current.save(
      kind: 'app',
      title: '',
      payload: {},
      attachments: {'heavy': 'data'},
    );
    final connection = await database.database;
    connection.execute('''CREATE TRIGGER forbid_attachment_rewrite
      BEFORE UPDATE ON report_draft_attachments
      BEGIN SELECT RAISE(ABORT, 'heavy attachment rewritten'); END''');
    await save(current, 'new text');
    expect((await store.read('one'))!.attachments, {'heavy': 'data'});
    expect(current.revision, 2);
  });

  test(
    'finish stops already queued and future autosaves without resurrecting a draft',
    () async {
      final current = session('one');
      await save(current, 'first');
      final queued = save(current, 'late');
      final finish = current.finish();
      await Future.wait([queued, finish, save(current, 'even later')]);
      expect(await store.read('one'), isNull);
      await current.finish();
      expect(await store.list(), isEmpty);
    },
  );

  test('an old form cannot finish or overwrite a newer revision', () async {
    final first = session('one');
    await save(first, 'first');
    final second = session('one', revision: first.revision);
    await save(second, 'newer work');
    await expectLater(first.finish(), throwsA(isA<ReportDraftConflict>()));
    await expectLater(
      save(first, 'stale write'),
      throwsA(isA<ReportDraftConflict>()),
    );
    expect((await store.read('one'))!.payload['description'], 'newer work');
    await second.finish();
    expect(await store.read('one'), isNull);
  });

  test(
    'explicit discard prevents a previously opened form from recreating its row',
    () async {
      final current = session('one');
      await save(current, 'first');
      await store.delete('one');
      await expectLater(
        save(current, 'late'),
        throwsA(isA<ReportDraftConflict>()),
      );
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'empty book form creates no draft and incomplete correction is restored exactly',
    () async {
      const initial = {'details': '', 'mode': 'free', 'proposed': ''};
      final target = {
        'bookTitle': 'Book A',
        'source': {
          'bookId': 12,
          'lineIndex': 8,
          'originalLine': '<b>אב</b> &amp; ג',
        },
        'reportNote': 'literal <b> note',
      };
      final empty = BookReportDraftCubit(
        target: target,
        initialForm: initial,
        store: store,
      );
      await empty.close();
      expect(await store.list(), isEmpty);
      final current = BookReportDraftCubit(
        target: target,
        initialForm: initial,
        store: store,
      );
      current.updateForm({
        ...initial,
        'mode': 'correction',
        'proposed': '<b>',
        'selectionStart': 1,
        'selectionEnd': 3,
      });
      await current.close();
      final record = (await store.read(current.id))!;
      final resumed = BookReportDraftCubit(
        target: Map<String, dynamic>.from(record.payload['target'] as Map),
        initialForm: initial,
        restored: record,
        store: store,
      );
      expect(resumed.target['bookTitle'], 'Book A');
      expect(
        (resumed.target['source'] as Map)['originalLine'],
        '<b>אב</b> &amp; ג',
      );
      expect(resumed.target['reportNote'], 'literal <b> note');
      expect(resumed.state.form['proposed'], '<b>');
      expect(resumed.state.form['mode'], 'correction');
      expect(resumed.state.form['selectionStart'], 1);
      await resumed.complete();
      resumed.updateForm({'details': 'late callback'});
      await resumed.flush();
      await resumed.close();
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'completed old session preserves a newer revision and its attachments',
    () async {
      final first = session('one');
      await save(first, 'delivered');
      final second = session('one', revision: first.revision);
      await second.save(
        kind: ReportDraftStore.appKind,
        title: 'newer',
        payload: {'description': 'newer work'},
        attachments: {'images': ['new exact bytes']},
      );
      final newer = (await store.read('one'))!;

      await first.finish(preserveNewerRevision: true);
      expect(first.isFinished, isTrue);
      await save(first, 'late callback');
      final preserved = (await store.read('one'))!;
      expect(preserved.revision, newer.revision);
      expect(preserved.payload, newer.payload);
      expect(preserved.attachments, newer.attachments);
      await second.finish();
    },
  );

  test('completion keeps real storage failures retryable', () async {
    final current = session('one');
    await save(current, 'keep after IO failure');
    final connection = await database.database;
    connection.execute('''CREATE TRIGGER reject_draft_delete
      BEFORE DELETE ON report_drafts
      BEGIN SELECT RAISE(ABORT, 'storage unavailable'); END''');

    await expectLater(
      current.finish(preserveNewerRevision: true),
      throwsA(isNot(isA<ReportDraftConflict>())),
    );
    expect(current.isFinished, isFalse);
    expect(
      (await store.read('one'))!.payload['description'],
      'keep after IO failure',
    );

    connection.execute('DROP TRIGGER reject_draft_delete');
    await current.finish(preserveNewerRevision: true);
    expect(current.isFinished, isTrue);
    expect(await store.read('one'), isNull);
  });

  test(
    'book edits keep the draft row but use separate delivery identities',
    () async {
      const initial = {'details': '', 'mode': 'free'};
      const target = {'bookTitle': 'Exact source book', 'lineNumber': 12};
      final first = BookReportDraftCubit(
        target: target,
        initialForm: initial,
        store: store,
      );
      first.updateForm({...initial, 'details': 'first delivery'});
      await first.flush();
      final firstId = first.reportId;
      final firstRecord = (await store.read(first.id))!;
      final second = BookReportDraftCubit(
        target: target,
        initialForm: initial,
        restored: firstRecord,
        store: store,
      );
      expect(second.id, first.id);
      expect(second.reportId, firstId);
      second.updateForm(Map<String, dynamic>.from(second.state.form));
      await second.flush();
      expect(second.reportId, firstId);
      expect((await store.read(first.id))!.revision, firstRecord.revision);

      second.updateForm({...initial, 'details': 'second delivery'});
      await second.flush();
      expect(second.reportId, isNot(firstId));
      final newer = (await store.read(first.id))!;
      expect(newer.payload['reportId'], second.reportId);
      await first.complete();
      first.updateForm({...initial, 'details': 'late callback'});
      await first.close();
      expect(first.isCompleted, isTrue);
      expect((await store.read(second.id))!.payload, newer.payload);

      final reopened = BookReportDraftCubit(
        target: target,
        initialForm: initial,
        restored: newer,
        store: store,
      );
      expect(reopened.reportId, second.reportId);
      await second.close();
      await reopened.complete();
      await reopened.close();
      expect(await store.list(), isEmpty);
    },
  );
}

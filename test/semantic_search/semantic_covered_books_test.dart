import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';

import 'semantic_test_support.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('semantic_covered_'));
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  SemanticCoveredBooksSummary answer(String setKey, List<String> paths) =>
      SemanticCoveredBooksSummary(filePaths: paths, setKey: setKey);

  int computations(FakeBackend backend) =>
      backend.calls.where((call) => call == 'coveredBooks').length;

  test('חישוב אחד לקוראים במקביל, ונשמר עד שמשהו משתנה', () async {
    installModelFiles(root);
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1', 'id:2'])
      ..coveredBooksGate = gate;
    final repo = buildRepository(root: root, backend: backend);

    expect(repo.coveredBookFilePaths, isNull);
    final first = repo.loadCoveredBookFilePaths();
    final second = repo.loadCoveredBookFilePaths();
    await waitFor(() => computations(backend) == 1);
    gate.complete();
    backend.coveredBooksGate = null;

    expect(await first, {'id:1', 'id:2'});
    expect(identical(await first, await second), isTrue);
    expect(await repo.loadCoveredBookFilePaths(), {'id:1', 'id:2'});
    expect(computations(backend), 1);
    expect(repo.coveredBookFilePaths, {'id:1', 'id:2'});
    expect(backend.calls, isNot(contains('open')));
  });

  test('שינוי באינדקס הלקסיקלי מחשב מחדש', () async {
    installModelFiles(root);
    var stamp = 'index-1';
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(
      root: root,
      backend: backend,
      indexStamp: () async => stamp,
    );

    expect(await repo.loadCoveredBookFilePaths(), {'id:1'});
    stamp = 'index-2';
    backend.coveredBooksValue = answer('set-1', ['id:1', 'uid:7']);

    expect(await repo.loadCoveredBookFilePaths(), {'id:1', 'uid:7'});
    expect(computations(backend), 2);
  });

  test('שינוי דור וקטורים מכלי חיצוני מחשב מחדש גם באותו אינדקס', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(root: root, backend: backend);
    expect(await repo.loadCoveredBookFilePaths(), {'id:1'});

    backend
      ..coveredBooksStampValue = 'new generation'
      ..coveredBooksValue = answer('set-2', ['uid:7']);
    expect(await repo.loadCoveredBookFilePaths(), {'uid:7'});
    expect(computations(backend), 2);
  });

  test('שינוי באינדקס באמצע הסריקה פוסל את התשובה הישנה', () async {
    installModelFiles(root);
    var stamp = 'index-1';
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1'])
      ..coveredBooksGate = gate;
    final repo = buildRepository(
      root: root,
      backend: backend,
      indexStamp: () async => stamp,
    );
    final loading = repo.loadCoveredBookFilePaths();
    await waitFor(() => computations(backend) == 1);

    stamp = 'index-2';
    backend
      ..coveredBooksValue = answer('set-1', ['uid:7'])
      ..coveredBooksGate = null;
    gate.complete();

    expect(await loading, {'uid:7'});
    expect(computations(backend), 2);
  });

  test('התקנת וקטורים מבטלת את התשובה; אותו setKey שומר על אותו סט', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(
      root: root,
      backend: backend,
      locator: FakeLocator(releaseV30()),
    );
    await repo.enableAndDownload();
    final before = await repo.loadCoveredBookFilePaths();
    expect(before, {'id:1'});

    backend.vectors = SemanticVectorsSummary.absent;
    await repo.enableAndDownload();
    expect(repo.coveredBookFilePaths, isNull);

    final same = await repo.loadCoveredBookFilePaths();
    expect(computations(backend), 2);
    expect(identical(same, before), isTrue);

    backend.vectors = SemanticVectorsSummary.absent;
    await repo.enableAndDownload();
    backend.coveredBooksValue = answer('set-2', ['id:1', 'id:3']);
    expect(await repo.loadCoveredBookFilePaths(), {'id:1', 'id:3'});
  });

  test('סגירת ה-session (העברת ספרייה) מבטלת את התשובה', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(root: root, backend: backend);
    await repo.loadCoveredBookFilePaths();

    await repo.releaseForLibraryMove();
    expect(repo.coveredBookFilePaths, isNull);
    expect(await repo.loadCoveredBookFilePaths(), isNull);
    repo.finishLibraryMove();

    expect(await repo.loadCoveredBookFilePaths(), {'id:1'});
    expect(computations(backend), 2);
  });

  test('כשל במנוע או בלי וקטורים — null', () async {
    installModelFiles(root);
    final backend = FakeBackend()..vectors = installedV30;
    final repo = buildRepository(root: root, backend: backend);
    expect(await repo.loadCoveredBookFilePaths(), isNull);
    expect(repo.coveredBookFilePaths, isNull);

    final empty = buildRepository(
      root: Directory('${root.path}/empty')..createSync(),
      backend: FakeBackend(),
    );
    expect(await empty.loadCoveredBookFilePaths(), isNull);
  });

  test('ביטול באמצע (העברת ספרייה) מחזיר null ולא שומר תשובה', () async {
    installModelFiles(root);
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1'])
      ..coveredBooksGate = gate;
    final repo = buildRepository(root: root, backend: backend);
    final loading = repo.loadCoveredBookFilePaths();
    await waitFor(() => computations(backend) == 1);
    final moving = repo.releaseForLibraryMove();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    await moving;
    expect(await loading, isNull);
    expect(repo.coveredBookFilePaths, isNull);
  });

  test('בלי הסכמה אין חישוב', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(
      root: root,
      backend: backend,
      consent: FakeConsentStore(SearchFeedbackConsent.declined),
    );
    expect(await repo.loadCoveredBookFilePaths(), isNull);
    expect(computations(backend), 0);
  });

  test('עובד גם כשה-session פתוח', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(root: root, backend: backend);
    await repo.ensureOpen();
    expect(await repo.loadCoveredBookFilePaths(), {'id:1'});
  });

  test('פתיחת ה-session אינה מבטלת את התשובה', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = installedV30
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(root: root, backend: backend);
    await repo.loadCoveredBookFilePaths();
    await repo.ensureOpen();
    expect(repo.coveredBookFilePaths, {'id:1'});
    expect(await repo.loadCoveredBookFilePaths(), {'id:1'});
    expect(computations(backend), 1);
  });

  test('התקנה באמצע החישוב: התשובה הישנה לא נשמרת ומחושבת מחדש', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..coveredBooksValue = answer('set-1', ['id:1']);
    final repo = buildRepository(
      root: root,
      backend: backend,
      locator: FakeLocator(releaseV30()),
    );
    await repo.enableAndDownload();
    final gate = Completer<void>();
    backend.coveredBooksGate = gate;
    final loading = repo.loadCoveredBookFilePaths();
    await waitFor(() => computations(backend) == 1);
    backend.coveredBooksGate = null;

    backend.vectors = SemanticVectorsSummary.absent;
    await repo.enableAndDownload();
    backend.coveredBooksValue = answer('set-2', ['id:3']);
    gate.complete();

    expect(await loading, {'id:3'});
    expect(computations(backend), 2);
    expect(repo.coveredBookFilePaths, {'id:3'});
  });

  group('SemanticSearchBloc', () {
    test('הרשימה מתאפסת כשהחיפוש אינו שמיש וכשהטעינה נכשלת', () async {
      final repo = _ScriptedRepository();
      final bloc = SemanticSearchBloc(repository: repo)
        ..add(const SemanticSearchStarted())
        ..add(const SemanticCoveredBooksRequested());
      addTearDown(bloc.close);
      await waitFor(() => bloc.state.coveredBookFilePaths != null);
      expect(bloc.state.coveredBookFilePaths, {'id:1'});

      repo.next = null;
      repo.emit(_availability(SemanticAvailabilityPhase.ready));
      await waitFor(() => bloc.state.coveredBookFilePaths == null);
      expect(bloc.state.coveredBookFilePaths, isNull);

      repo.next = {'id:2'};
      repo.emit(_availability(SemanticAvailabilityPhase.ready));
      await waitFor(() => bloc.state.coveredBookFilePaths != null);
      expect(bloc.state.coveredBookFilePaths, {'id:2'});

      repo.emit(_availability(SemanticAvailabilityPhase.installing));
      await waitFor(() => bloc.state.coveredBookFilePaths == null);
      expect(bloc.state.coveredBookFilePaths, isNull);
    });
  });
}

SemanticAvailability _availability(SemanticAvailabilityPhase phase) =>
    SemanticAvailability(phase: phase, consentGranted: true);

class _ScriptedRepository extends SemanticSearchRepository {
  _ScriptedRepository()
    : super(
        backend: FakeBackend(),
        consent: () => FakeConsentStore(),
        settings: FakeSettingsStore(),
      );

  SemanticAvailability current = _availability(
    SemanticAvailabilityPhase.ready,
  );
  final _controller = StreamController<SemanticAvailability>.broadcast();
  Set<String>? next = {'id:1'};

  void emit(SemanticAvailability value) {
    current = value;
    _controller.add(value);
  }

  @override
  SemanticAvailability get availability => current;

  @override
  Stream<SemanticAvailability> get availabilityChanges => _controller.stream;

  @override
  Future<SemanticAvailability> refresh() async => current;

  @override
  Future<Set<String>?> loadCoveredBookFilePaths() async => next;
}

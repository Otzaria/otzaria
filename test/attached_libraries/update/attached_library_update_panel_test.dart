import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/attached_libraries/view/attached_libraries_panel.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import '../../helpers/memory_settings_cache.dart';

const _source = AttachedLibraryUpdateSource(
  libraryId: 'lib-a',
  manifestUrl: 'https://updates.example.org/a/manifest.json',
  publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
);

class _FakeRepository extends AttachedLibrariesRepository {
  _FakeRepository(this.items) : super(copyByDefault: false);

  List<AttachedLibrary> items;
  final _controller = StreamController<Set<String>>.broadcast();

  @override
  List<AttachedLibrary> get libraries => items;

  @override
  List<String> get folders => const [];

  @override
  Stream<Set<String>> get changes => _controller.stream;

  @override
  Future<AttachResult> importFile(
    String sourcePath, {
    AttachedLibraryMode? mode,
  }) async {
    final library = _library('new', source: _source);
    items = [...items, library];
    return AttachResult.success(library);
  }
}

class _FakeUpdates extends AttachedLibraryUpdateService {
  final notifier = ValueNotifier<Map<String, AttachedUpdateStatus>>({});
  final checked = <String>[];
  final installed = <String>[];
  final cancelled = <String>[];

  @override
  ValueListenable<Map<String, AttachedUpdateStatus>> get statuses => notifier;

  @override
  AttachedUpdateStatus statusOf(AttachedLibrary library) =>
      notifier.value[library.path] ?? const AttachedUpdateIdle();

  @override
  Future<void> restorePending() async {}

  @override
  Future<AttachedUpdateStatus> check(AttachedLibrary library) async {
    checked.add(library.slug);
    return const AttachedUpdateIdle();
  }

  @override
  Future<void> install(AttachedLibrary requested) async =>
      installed.add(requested.slug);

  @override
  void cancel(AttachedLibrary library) => cancelled.add(library.slug);
}

AttachedLibrary _library(
  String name, {
  AttachedLibraryUpdateSource? source,
  bool mismatch = false,
}) => AttachedLibrary(
  slug: name,
  displayName: name,
  path: 'C:/dbs/$name.db',
  bookCount: 3,
  addedAt: DateTime(2026),
  updateSource: source,
  updateSourceMismatch: mismatch,
  fingerprint: const AttachedLibraryFingerprint(
    size: 1,
    modifiedMs: 1,
    dbVersion: '1',
  ),
);

AttachedUpdateOffer _offer() => AttachedUpdateOffer(
  manifest: const AttachedUpdateManifest(
    libraryId: 'lib-a',
    dbVersion: 2,
    releaseNotes: 'release notes text',
    full: AttachedUpdateArtifact(
      compression: AttachedUpdateCompression.zstd,
      size: 3 * 1024 * 1024,
      sha256: '',
      parts: [
        AttachedUpdatePart(
          url: 'https://a.example.net/p1',
          size: 1024 * 1024,
          sha256: '',
        ),
        AttachedUpdatePart(
          url: 'https://A.example.net/p2',
          size: 1024 * 1024,
          sha256: '',
        ),
      ],
    ),
    deltas: [
      AttachedUpdateDelta(
        fromDbVersion: 1,
        fromSha256: '',
        artifact: AttachedUpdateArtifact(
          compression: AttachedUpdateCompression.zstd,
          size: 1,
          sha256: '',
          parts: [
            AttachedUpdatePart(
              url: 'https://cdn.example.com/d1',
              size: 1,
              sha256: '',
            ),
          ],
        ),
      ),
    ],
  ),
  manifestBytes: Uint8List(0),
  signature: Uint8List(0),
  domain: 'updates.example.org',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<(AttachedLibrariesBloc, _FakeUpdates)> pumpPanel(
    WidgetTester tester,
    List<AttachedLibrary> libraries, {
    Map<String, AttachedUpdateStatus> statuses = const {},
  }) async {
    final updates = _FakeUpdates()..notifier.value = statuses;
    final bloc = AttachedLibrariesBloc(
      addLibraryEvent: (_) {},
      repository: _FakeRepository(libraries),
      updates: updates,
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AttachedLibrariesBloc>.value(
            value: bloc,
            child: const SingleChildScrollView(
              child: AttachedLibrariesPanel(supportsLinking: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (bloc, updates);
  }

  testWidgets('no source: chip only, nothing to check', (tester) async {
    await pumpPanel(tester, [_library('a')]);
    expect(find.text('אין מקור עדכונים'), findsOneWidget);
    expect(find.text('בדוק עדכונים'), findsNothing);
  });

  testWidgets('changed source: warning chip, nothing to check', (
    tester,
  ) async {
    await pumpPanel(tester, [_library('a', source: _source, mismatch: true)]);
    expect(find.text('מקור העדכון השתנה — לא יעודכן'), findsOneWidget);
    expect(find.text('בדוק עדכונים'), findsNothing);
  });

  testWidgets('signed source: domain chip and a manual check', (
    tester,
  ) async {
    final (_, updates) = await pumpPanel(tester, [
      _library('a', source: _source),
    ]);
    expect(find.text('חתום · updates.example.org'), findsOneWidget);
    await tester.tap(find.text('בדוק עדכונים'));
    await tester.pump();
    expect(updates.checked, ['a']);
  });

  group('available update', () {
    Future<_FakeUpdates> openDialog(WidgetTester tester) async {
      final library = _library('a', source: _source);
      final (_, updates) = await pumpPanel(
        tester,
        [library],
        statuses: {library.path: AttachedUpdateAvailable(_offer())},
      );
      expect(find.text('עדכון זמין (גרסה 2)'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionButton, 'עדכן'));
      await tester.pumpAndSettle();
      expect(find.text('מקור: updates.example.org (חתום)'), findsOneWidget);
      expect(
        find.text('הקבצים יורדו מ: a.example.net, cdn.example.com'),
        findsOneWidget,
      );
      expect(find.text('גודל ההורדה: 2.0 MB'), findsOneWidget);
      expect(find.text('גרסה: 2'), findsOneWidget);
      expect(find.text('release notes text'), findsOneWidget);
      return updates;
    }

    testWidgets('confirming installs', (tester) async {
      final updates = await openDialog(tester);
      await tester.tap(find.widgetWithText(ActionButton, 'עדכן').last);
      await tester.pumpAndSettle();
      expect(updates.installed, ['a']);
    });

    testWidgets('declining installs nothing', (tester) async {
      final updates = await openDialog(tester);
      await tester.tap(find.widgetWithText(ActionButton, 'ביטול'));
      await tester.pumpAndSettle();
      expect(updates.installed, isEmpty);
    });
  });

  testWidgets('download in progress: bar and cancel', (tester) async {
    final library = _library('a', source: _source);
    final (_, updates) = await pumpPanel(
      tester,
      [library],
      statuses: {
        library.path: AttachedUpdateInProgress(
          _offer(),
          phase: AttachedUpdatePhase.download,
          received: 1024 * 1024,
          total: 2 * 1024 * 1024,
        ),
      },
    );
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
    expect(find.text('מוריד 1.0 MB מתוך 2.0 MB'), findsOneWidget);
    await tester.tap(find.text('ביטול'));
    await tester.pump();
    expect(updates.cancelled, ['a']);
  });

  testWidgets('failure: error text and a retry that keeps the offer', (
    tester,
  ) async {
    final library = _library('a', source: _source);
    await pumpPanel(
      tester,
      [library],
      statuses: {
        library.path: AttachedUpdateFailed(
          AttachedUpdateError.noSpace,
          offer: _offer(),
          requiredBytes: 5 * 1024 * 1024,
        ),
      },
    );
    expect(find.text('אין מספיק מקום פנוי (נדרשים 5.0 MB)'), findsOneWidget);
    expect(find.widgetWithText(ActionButton, 'עדכן'), findsOneWidget);
  });

  testWidgets('status changes from the service reach the card', (
    tester,
  ) async {
    final library = _library('a', source: _source);
    final (_, updates) = await pumpPanel(tester, [library]);
    updates.notifier.value = {library.path: const AttachedUpdateInstalled(2)};
    await tester.pump();
    await tester.pump();
    expect(find.text('עודכן לגרסה 2'), findsOneWidget);
  });

  testWidgets('attaching a database with a source shows its domain', (
    tester,
  ) async {
    final (bloc, _) = await pumpPanel(tester, []);
    bloc.add(const ImportAttachedLibraryFile('C:/x/new.db'));
    await tester.pumpAndSettle();
    expect(find.text('המסד צורף'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.textContaining('updates.example.org'),
      ),
      findsOneWidget,
    );
  });
}

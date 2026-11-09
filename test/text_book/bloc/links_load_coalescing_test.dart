import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  final calls = <({List<String>? targets, int start})>[];
  final gate = Completer<void>();
  bool failFirst = false;
  bool failSecond = false;
  Completer<void>? secondCallGate;

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    final targets = targetBookTitles?.toList();
    calls.add((targets: targets, start: startIndex));
    if (calls.length == 1) {
      await gate.future;
      if (failFirst) throw StateError('כשל בדיקה');
    }
    if (calls.length == 2) {
      await secondCallGate?.future;
      if (failSecond) throw StateError('כשל בדיקה אחרי חלון שמור');
    }
    return [
      for (final target in targets ?? [SeforimFixtureIds.rashiTitle])
        Link(
          heRef: target,
          index1: 1,
          path2: target,
          index2: 1,
          connectionType: 'commentary',
        ),
    ];
  }
}

Future<void> _settle() async {
  // פתרון ברירות המחדל עובר ב-worker האמיתי של SQLite.
  for (var i = 0; i < 8; i++) {
    await SqliteDataProvider.instance.getBookTocFromDb(
      SeforimFixtureIds.bereshitTitle,
    );
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('הטעינה לא הסתיימה');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _Repository repository;
  late TextBook book;

  TextBookLoaded loaded() => TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['טקסט'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [SeforimFixtureIds.rashiTitle],
    commentatorsLoaded: true,
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
  );

  TextBookBloc createBloc() => TextBookBloc(
    repository: repository,
    initialState: TextBookInitial.named(book, 0, false, const []),
  );

  const global = RefreshLinksForCurrentWindow(reason: 'global');
  const workspace = RefreshLinksForCurrentWindow(
    reason: 'workspace',
    workspaceId: 'ws',
  );

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    temp = Directory.systemTemp.createTempSync('links-coalescing-');
    AppPaths.debugOverrideDataRootPath(temp.path);
    final fixture = SeforimFixtureDb.create(temp, SeforimFixtureVariant.full);
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      fixture,
    );
    await SqliteDataProvider.instance.initialize();
    await Settings.setValue<bool>('page_shape_global_visibility_right', false);
    await Settings.setValue<bool>(
      'page_shape_workspace_visibility_right_ws',
      true,
    );
    await PageShapeSettingsManager.setUseWorkspaceSpecificSettings('ws', true);
    book = TextBook(
      title: SeforimFixtureIds.bereshitTitle,
      categoryId: SeforimFixtureIds.torahCategoryId,
    );
    repository = _Repository();
  });

  tearDown(() async {
    if (!repository.gate.isCompleted) repository.gate.complete();
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    AppPaths.debugOverrideDataRootPath(null);
    temp.deleteSync(recursive: true);
  });

  blocTest<TextBookBloc, TextBookState>(
    'רענון שולחן עבודה חופף לרענון גלובלי שומר את המפרש שלו',
    build: createBloc,
    seed: loaded,
    act: (bloc) async {
      bloc.add(global);
      bloc.add(workspace);
      await _settle();
      expect(repository.calls.first.targets, isEmpty);
      repository.gate.complete();
      await _waitFor(
        () => (bloc.state as TextBookLoaded).links.any(
          (link) => link.path2 == SeforimFixtureIds.rashiTitle,
        ),
      );
    },
    verify: (_) => expect(repository.calls.map((call) => call.targets), [
      <String>[],
      [SeforimFixtureIds.rashiTitle],
    ]),
  );

  blocTest<TextBookBloc, TextBookState>(
    'רענונים זהים חופפים מסתפקים בשאילתה אחת',
    build: createBloc,
    seed: loaded,
    act: (bloc) async {
      bloc.add(workspace);
      bloc.add(workspace);
      bloc.add(workspace);
      await _settle();
      repository.gate.complete();
      await _waitFor(() => !(bloc.state as TextBookLoaded).linksLoading);
      await _settle();
    },
    verify: (_) => expect(repository.calls, hasLength(1)),
  );

  for (final failFirst in [false, true]) {
    blocTest<TextBookBloc, TextBookState>(
      'טעינת פרק מפורשת קודמת לעדכון מפרשים אוטומטי, כשל=$failFirst',
      build: createBloc,
      seed: () => loaded().copyWith(showPageShapeView: false),
      act: (bloc) async {
        repository.failFirst = failFirst;
        bloc.add(global);
        await _waitFor(() => repository.calls.isNotEmpty);
        bloc.add(const LoadAllLinksForIndices([2000]));
        bloc.add(
          const UpdateAvailableCommentators([SeforimFixtureIds.rashiTitle], []),
        );
        await _settle();
        repository.gate.complete();
        await _waitFor(
          () => (bloc.state as TextBookLoaded).links.any(
            (link) => link.path2 == SeforimFixtureIds.rashiTitle,
          ),
        );
        await _settle();
      },
      verify: (_) {
        expect(repository.calls, hasLength(2));
        expect(repository.calls.last.targets, isNull);
        expect(
          repository.calls.last.start,
          2000 - TextBookBloc.linkLookBehindLines,
        );
      },
    );
  }

  blocTest<TextBookBloc, TextBookState>(
    'רענון מאולץ ממתין אינו נבלם במטמון לאחר כשל',
    build: createBloc,
    seed: loaded,
    act: (bloc) async {
      repository.gate.complete();
      bloc.add(workspace);
      await _waitFor(
        () => (bloc.state as TextBookLoaded).links.isNotEmpty,
      );
      repository.secondCallGate = Completer<void>();
      repository.failSecond = true;
      bloc.add(workspace);
      await _waitFor(() => repository.calls.length == 2);
      bloc.add(workspace);
      await _settle();
      repository.secondCallGate!.complete();
      await _waitFor(() => repository.calls.length == 3);
      await _settle();
    },
    verify: (_) => expect(repository.calls, hasLength(3)),
  );

  blocTest<TextBookBloc, TextBookState>(
    'מעבר נוסף לשולחן גלובלי אינו משחזר בקשת workspace ישנה',
    build: createBloc,
    seed: loaded,
    act: (bloc) async {
      bloc.add(workspace);
      await _waitFor(() => repository.calls.isNotEmpty);
      bloc.add(workspace);
      bloc.add(global);
      await _settle();
      repository.gate.complete();
      await _waitFor(() => repository.calls.length == 2);
      await _waitFor(() => !(bloc.state as TextBookLoaded).linksLoading);
      await _settle();
    },
    verify: (bloc) {
      expect(repository.calls.map((call) => call.targets), [
        [SeforimFixtureIds.rashiTitle],
        <String>[],
      ]);
      expect((bloc.state as TextBookLoaded).links, isEmpty);
    },
  );

  test('טעינת תוכן חדשה מבטלת תוצאה ובקשה ממתינה מהטעינה הקודמת', () async {
    final bloc = createBloc()..emit(loaded());
    addTearDown(bloc.close);
    bloc.add(workspace);
    await _waitFor(() => repository.calls.isNotEmpty);
    bloc.add(workspace);
    await _settle();
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
        preserveState: true,
      ),
    );
    await _waitFor(() => repository.calls.length == 2);
    await _waitFor(() => !(bloc.state as TextBookLoaded).linksLoading);
    repository.gate.complete();
    await _settle();
    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.targets, isEmpty);
    expect((bloc.state as TextBookLoaded).links, isEmpty);
  });

  test('סגירת ה-bloc מבטלת בקשה ממתינה', () async {
    final bloc = createBloc()..emit(loaded());
    bloc.add(global);
    bloc.add(workspace);
    await _settle();
    await bloc.close();
    repository.gate.complete();
    await _settle();
    expect(repository.calls, hasLength(1));
  });
}

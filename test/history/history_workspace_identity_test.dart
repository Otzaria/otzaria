import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/backup/backup_import_merge.dart';
import 'package:otzaria/settings/services/backup/backup_merge.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

final _book = PdfBook(title: 'ביצה', path: '/nonexistent/beitza.pdf');

Bookmark _entry(int index, {String? id, String? name, String? slot}) =>
    Bookmark(
      ref: 'ביצה $index',
      book: _book,
      index: index,
      workspaceId: id,
      workspaceName: name,
      historySlot: slot,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late UserStateDatabase database;
  late UserStateListStore store;
  late HistoryRepository repository;
  late HistoryBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('history_workspace_');
    database = UserStateDatabase.openAt('${directory.path}/state.db');
    UserStateDatabase.debugWriteInline = true;
    store = UserStateListStore(database: database);
    repository = HistoryRepository(store: store);
    bloc = HistoryBloc(repository);
    await bloc.stream.firstWhere((state) => state is HistoryLoaded);
  });

  tearDown(() async {
    await bloc.close();
    store.dispose();
    database.close();
    UserStateDatabase.debugWriteInline = false;
    directory.deleteSync(recursive: true);
  });

  Future<void> add(Bookmark entry) async {
    final written = bloc.stream.firstWhere(
      (state) =>
          state is HistoryLoaded && state.history.first.index == entry.index,
    );
    bloc.add(BulkAddHistory([entry]));
    await written;
  }

  Future<void> capture(PdfBookTab tab, String id, String name) async {
    bloc.add(SetCurrentWorkspaceName(name, workspaceId: id));
    bloc.add(CaptureStateForHistory(tab));
    await pumpEventQueue();
  }

  for (final slot in <String?>[null, 'shared-slot']) {
    test(
      'SQLite: שחזור שולחנות עם אותו slot שומר שתי לכידות ממתינות: $slot',
      () async {
        Workspace restored(String id, int index) {
          final original = PdfBookTab(book: _book, pageNumber: index)
            ..historySlot = slot;
          final raw = Workspace(
            id: id,
            name: 'סדר $id',
            tabs: [original],
          ).toJson();
          original.dispose();
          return Workspace.fromJson(
            jsonDecode(jsonEncode(raw)) as Map<String, dynamic>,
          );
        }

        final a = restored('A', 25);
        final b = restored('B', 3);
        final tabA = a.tabs.single as PdfBookTab
          ..pdfViewerController = _ReadyPdfController(25);
        final tabB = b.tabs.single as PdfBookTab
          ..pdfViewerController = _ReadyPdfController(3);
        addTearDown(tabA.dispose);
        addTearDown(tabB.dispose);
        expect(tabA.historySlot, slot);
        expect(tabB.historySlot, slot);

        await capture(tabA, a.id, a.name);
        await capture(tabB, b.id, b.name);
        final flushed = bloc.stream.firstWhere(
          (state) => state is HistoryLoaded && state.history.isNotEmpty,
        );
        bloc.add(FlushHistory());
        await flushed;
        expect(
          {
            for (final entry in await repository.loadHistory())
              entry.workspaceId: entry.index,
          },
          {'A': 25, 'B': 3},
        );
      },
    );

    test('SQLite: שתי כתיבות עם אותו slot נפרדות לפי שולחן: $slot', () async {
      await add(_entry(25, id: 'A', name: 'סדר', slot: slot));
      await add(_entry(3, id: 'B', name: 'סדר', slot: slot));
      expect(await repository.loadHistory(), hasLength(2));
      await add(_entry(26, id: 'A', name: 'שם חדש', slot: slot));
      final saved = await repository.loadHistory();
      expect(
        {for (final entry in saved) entry.workspaceId: entry.index},
        {'A': 26, 'B': 3},
      );

      bloc.add(RemoveHistory(0));
      await bloc.stream.firstWhere((state) => state.history.length == 1);
      expect((await repository.loadHistory()).single.workspaceId, 'B');
    });

    test(
      'SQLite: פתיחה מהיסטוריה בשולחן אחר אינה דורסת את המקור: $slot',
      () async {
        final a = _entry(25, id: 'A', name: 'סדר א', slot: slot);
        await add(a);
        final tab = tabFromBookmark(a) as PdfBookTab
          ..pdfViewerController = _ReadyPdfController(26);
        addTearDown(tab.dispose);
        await capture(tab, 'B', 'סדר ב');
        final flushed = bloc.stream.firstWhere(
          (state) => state.history.first.index == 26,
        );
        bloc.add(FlushHistory());
        await flushed;
        expect(
          {
            for (final entry in await repository.loadHistory())
              entry.workspaceId: entry.index,
          },
          {'A': 25, 'B': 26},
        );
      },
    );
  }

  test(
    'SQLite: רשומות ישנות לפי שם נשמרות בנפרד ומשודרגות בלי כפילות',
    () async {
      await add(_entry(25, name: 'סדר א'));
      await add(_entry(3, name: 'סדר ב'));
      expect(await repository.loadHistory(), hasLength(2));
      await add(_entry(26, id: 'A', name: 'סדר א'));
      final saved = await repository.loadHistory();
      expect(saved, hasLength(2));
      expect(saved.first.workspaceId, 'A');
      expect(saved.last.workspaceName, 'סדר ב');
    },
  );

  test('SQLite: רשומה בלי שולחן נשמרת לצד הרשומה המשויכת', () async {
    await add(_entry(25));
    await add(_entry(3, id: 'A', name: 'סדר א'));
    expect(await repository.loadHistory(), hasLength(2));
  });

  for (final split in [false, true]) {
    test(
      'SQLite: החלפת שולחן בזמן לכידה קבוצתית אינה משנה את הבעלות, split=$split',
      () async {
        bloc.add(SetCurrentWorkspaceName('סדר א', workspaceId: 'A'));
        await pumpEventQueue();
        final first = PdfBookTab(book: _book, pageNumber: 25)
          ..historySlot = 'first'
          ..pdfViewerController = _ReadyPdfController(
            25,
            onRead: () {
              bloc.add(SetCurrentWorkspaceName('סדר ב', workspaceId: 'B'));
            },
          );
        final second = PdfBookTab(book: _book, pageNumber: 3)
          ..historySlot = 'second'
          ..pdfViewerController = _ReadyPdfController(3);
        final written = bloc.stream.firstWhere(
          (state) => state.history.length == 2,
        );
        if (split) {
          final combined = CombinedTab(rightTab: second, leftTab: first);
          addTearDown(combined.dispose);
          bloc.add(AddHistory(combined));
        } else {
          addTearDown(first.dispose);
          addTearDown(second.dispose);
          bloc.add(AddHistoryForTabs([first, second]));
        }
        await written;
        await pumpEventQueue();
        expect(bloc.currentWorkspaceId, 'B');
        expect(
          (await repository.loadHistory()).map((entry) => entry.workspaceId),
          everyElement('A'),
        );
      },
    );
  }

  test('שאילתת חיפוש נשארת גלובלית לכל השולחנות', () async {
    Bookmark search(String id) => Bookmark(
      ref: 'ביצה',
      book: _book,
      index: id == 'A' ? 1 : 2,
      isSearch: true,
      workspaceId: id,
    );
    await add(search('A'));
    await add(search('B'));
    expect((await repository.loadHistory()).single.workspaceId, 'B');
  });

  for (final withIds in [false, true]) {
    test('גיבוי מתגלגל וייבוא משמרים שולחנות עם slot זהה, IDs=$withIds', () {
      final a = _entry(
        25,
        id: withIds ? 'A' : null,
        name: 'סדר א',
        slot: 'shared',
      );
      final b = _entry(
        3,
        id: withIds ? 'B' : null,
        name: 'סדר ב',
        slot: 'shared',
      );
      final merged = BackupMerge.merge(
        {
          'history': [a.toJson()],
        },
        {
          'history': [b.toJson()],
        },
        olderTimestamp: DateTime(2025, 1, 1),
        newerTimestamp: DateTime(2025, 6, 1),
        now: DateTime(2025, 7, 1),
      );
      expect(merged['history'] as List, hasLength(2));
      expect(BackupImportMerge.mergeHistory([a], [b]).merged, hasLength(2));
    });
  }

  test('גיבוי מתגלגל מעדכן אותו ID לאחר שינוי שם', () {
    final a = _entry(25, id: 'A', name: 'ישן');
    final newer = _entry(26, id: 'A', name: 'חדש');
    final merged = BackupMerge.merge(
      {
        'history': [a.toJson()],
      },
      {
        'history': [newer.toJson()],
      },
      olderTimestamp: DateTime(2025, 1, 1),
      newerTimestamp: DateTime(2025, 6, 1),
      now: DateTime(2025, 7, 1),
    );
    final history = merged['history'] as List;
    expect(history, hasLength(1));
    expect((history.single as Map)['index'], 26);
  });
}

class _ReadyPdfController extends PdfViewerController {
  _ReadyPdfController(this.page, {this.onRead});
  final int page;
  final void Function()? onRead;
  @override
  bool get isReady => true;
  @override
  int? get pageNumber {
    onRead?.call();
    return page;
  }
}

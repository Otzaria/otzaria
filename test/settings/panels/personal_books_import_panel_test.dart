import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/panels/personal_books_import_panel.dart';
import 'package:otzaria/settings/services/custom_folders/android_folder_import_channel.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/services/custom_folders/personal_books_import_service.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';

/// Fake בזיכרון — IO אמיתי בתוך testWidgets נתקע באזור ה-FakeAsync,
/// ולוגיקת הקבצים האמיתית מכוסה ב-personal_books_import_service_test.
class _FakeImportService extends PersonalBooksImportService {
  _FakeImportService() : super(folderPathOverride: _folderPath);

  static const _folderPath = 'C:/fake/imported';

  final List<String> fileNames = [];

  @override
  Future<PersonalBooksImportResult> copyFiles(List<String> sourcePaths) async {
    var copied = 0;
    var skipped = 0;
    for (final path in sourcePaths) {
      if (!PersonalBooksImportService.isSupportedFile(path)) {
        skipped++;
        continue;
      }
      final name = p.basename(path);
      if (!fileNames.contains(name)) fileNames.add(name);
      copied++;
    }
    return PersonalBooksImportResult(
      copied: copied,
      skippedUnsupported: skipped,
    );
  }

  @override
  Future<List<File>> listImportedFiles() async => [
    for (final name in fileNames) File(p.join(_folderPath, name)),
  ];

  @override
  Future<void> deleteImportedFile(String filePath) async {
    fileNames.remove(p.basename(filePath));
  }

  @override
  Future<PersonalBooksImportResult> keepValidCopiedFiles(
    List<String> copiedPaths,
  ) async {
    fileNames.addAll(copiedPaths.map(p.basename));
    return PersonalBooksImportResult(copied: copiedPaths.length);
  }
}

class _FakeFolderImport extends AndroidFolderImportChannel {
  _FakeFolderImport({this.fileCount = 2, this.holdCopy = false});

  final int fileCount;

  /// ההעתקה נשארת פתוחה עד [cancelCopy] — לבדיקת כפתור הביטול.
  final bool holdCopy;
  String? copiedTo;
  bool cancelCalled = false;
  Completer<FolderCopyResult>? _pendingCopy;

  @override
  Future<void> cancelCopy() async {
    cancelCalled = true;
    _pendingCopy?.complete(
      FolderCopyResult(
        copiedPaths: [p.join(copiedTo!, 'מסילת ישרים.txt')],
        errors: const [],
        cancelled: true,
      ),
    );
  }

  @override
  Future<PickedFolder?> pickFolder() async =>
      const PickedFolder(uri: 'content://tree/x', name: 'ספרי מוסר');

  @override
  Future<FolderScan> scanFolder(String uri, List<String> extensions) async =>
      FolderScan(fileCount: fileCount, totalBytes: 3 * 1024 * 1024);

  @override
  Future<FolderCopyResult> copyFolder(
    String uri,
    String destDir,
    List<String> extensions,
  ) async {
    copiedTo = destDir;
    if (holdCopy) return (_pendingCopy = Completer()).future;
    return FolderCopyResult(
      copiedPaths: [p.join(destDir, 'מסילת ישרים.txt')],
      errors: const [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeImportService service;
  late List<LibraryEvent> libraryEvents;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    service = _FakeImportService();
    libraryEvents = [];
  });

  CustomFoldersBloc buildBloc({
    required bool folderRegistered,
    required List<List<CustomFolder>> syncCalls,
    List<List<CustomFolder>>? saveCalls,
  }) {
    var folders = folderRegistered
        ? [
            CustomFolder(
              path: _FakeImportService._folderPath,
              addedAt: DateTime(2026),
            ),
          ]
        : <CustomFolder>[];
    return CustomFoldersBloc(
      addLibraryEvent: libraryEvents.add,
      loadFolders: () => folders,
      saveFolders: (newFolders) async {
        folders = newFolders;
        saveCalls?.add(newFolders);
      },
      syncFolders: (syncedFolders, {String? onlyFolderPath}) async {
        syncCalls.add(syncedFolders);
        return const FileSyncResult();
      },
      deleteFolderFromDb: (_) async {},
    )..add(const LoadCustomFolders());
  }

  // ספינר ה-ActionButton מוצג בזמן isSyncing ולכן pumpAndSettle עלול שלא
  // להתייצב — משתמשים ב-pumps מדודים.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required CustomFoldersBloc bloc,
    Future<List<String>?> Function()? pickFiles,
    AndroidFolderImportChannel? folderImport,
    bool showFolderImport = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<CustomFoldersBloc>.value(
            value: bloc,
            child: SingleChildScrollView(
              child: PersonalBooksImportPanel(
                service: service,
                pickFilesOverride: pickFiles,
                folderImport: folderImport,
                showFolderImport: showFolderImport,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('מציג את הספרים המיובאים לאחר פתיחת הרשימה', (tester) async {
    service.fileNames.add('מסילת ישרים.txt');
    final bloc = buildBloc(folderRegistered: true, syncCalls: []);

    await pumpPanel(tester, bloc: bloc);
    expect(find.text('1 ספרים מיובאים'), findsOneWidget);

    await tester.tap(find.text('הספרים שלי'));
    await settle(tester);

    expect(find.text('מסילת ישרים'), findsOneWidget);
  });

  testWidgets('ייבוא מעתיק את הקובץ ומפעיל סריקה כשהתיקייה כבר רשומה', (
    tester,
  ) async {
    final syncCalls = <List<CustomFolder>>[];
    final bloc = buildBloc(folderRegistered: true, syncCalls: syncCalls);

    await pumpPanel(
      tester,
      bloc: bloc,
      pickFiles: () async => ['C:/picked/שערי תשובה.txt'],
    );
    await tester.tap(find.text('ייבוא ספרים'));
    await settle(tester);

    expect(service.fileNames, ['שערי תשובה.txt']);
    expect(syncCalls, hasLength(1));
    expect(syncCalls.single.single.path, _FakeImportService._folderPath);
  });

  testWidgets('ייבוא ראשון רושם את התיקייה כתיקייה מותאמת אישית', (
    tester,
  ) async {
    final saveCalls = <List<CustomFolder>>[];
    final bloc = buildBloc(
      folderRegistered: false,
      syncCalls: [],
      saveCalls: saveCalls,
    );

    await pumpPanel(
      tester,
      bloc: bloc,
      pickFiles: () async => ['C:/picked/אורחות צדיקים.txt'],
    );
    await tester.tap(find.text('ייבוא ספרים'));
    await settle(tester);

    expect(service.fileNames, ['אורחות צדיקים.txt']);
    expect(saveCalls, hasLength(1));
    expect(saveCalls.single.single.path, _FakeImportService._folderPath);
  });

  testWidgets('ייבוא תיקייה: אישור עם ספירה, העתקה לתת-תיקייה וסריקה', (
    tester,
  ) async {
    final syncCalls = <List<CustomFolder>>[];
    final bloc = buildBloc(folderRegistered: true, syncCalls: syncCalls);
    final folderImport = _FakeFolderImport();

    await pumpPanel(
      tester,
      bloc: bloc,
      folderImport: folderImport,
      showFolderImport: true,
    );
    await tester.tap(find.text('ייבוא תיקייה'));
    await settle(tester);

    expect(
      find.text('נמצאו 2 קבצי ספרים (3.0 MB). להעתיק אותם לספרייה?'),
      findsOneWidget,
    );
    await tester.tap(find.text('ייבא'));
    await settle(tester);

    expect(
      folderImport.copiedTo,
      p.join(_FakeImportService._folderPath, 'ספרי מוסר'),
    );
    expect(service.fileNames, ['מסילת ישרים.txt']);
    expect(syncCalls, hasLength(1));
  });

  testWidgets('בטל ייבוא עוצר את ההעתקה ומשאיר את מה שכבר הועתק', (
    tester,
  ) async {
    final syncCalls = <List<CustomFolder>>[];
    final bloc = buildBloc(folderRegistered: true, syncCalls: syncCalls);
    final folderImport = _FakeFolderImport(holdCopy: true);

    await pumpPanel(
      tester,
      bloc: bloc,
      folderImport: folderImport,
      showFolderImport: true,
    );
    await tester.tap(find.text('ייבוא תיקייה'));
    await settle(tester);
    await tester.tap(find.text('ייבא'));
    await settle(tester);

    expect(find.text('ייבוא תיקייה'), findsNothing);
    await tester.tap(find.text('בטל ייבוא'));
    await settle(tester);

    expect(folderImport.cancelCalled, isTrue);
    expect(find.text('בטל ייבוא'), findsNothing);
    expect(service.fileNames, ['מסילת ישרים.txt']);
    expect(syncCalls, hasLength(1));
  });

  testWidgets('ביטול באישור לא מעתיק דבר', (tester) async {
    final syncCalls = <List<CustomFolder>>[];
    final bloc = buildBloc(folderRegistered: true, syncCalls: syncCalls);
    final folderImport = _FakeFolderImport();

    await pumpPanel(
      tester,
      bloc: bloc,
      folderImport: folderImport,
      showFolderImport: true,
    );
    await tester.tap(find.text('ייבוא תיקייה'));
    await settle(tester);
    await tester.tap(find.text('ביטול'));
    await settle(tester);

    expect(folderImport.copiedTo, isNull);
    expect(syncCalls, isEmpty);
  });

  testWidgets('תיקייה בלי ספרים לא פותחת אישור ולא מעתיקה', (tester) async {
    final bloc = buildBloc(folderRegistered: true, syncCalls: []);
    final folderImport = _FakeFolderImport(fileCount: 0);

    await pumpPanel(
      tester,
      bloc: bloc,
      folderImport: folderImport,
      showFolderImport: true,
    );
    await tester.tap(find.text('ייבוא תיקייה'));
    await settle(tester);

    expect(find.text('ייבא'), findsNothing);
    expect(folderImport.copiedTo, isNull);
  });

  testWidgets('בלי תמיכה בתיקייה הכפתור אינו מוצג', (tester) async {
    final bloc = buildBloc(folderRegistered: true, syncCalls: []);

    await pumpPanel(tester, bloc: bloc);

    expect(find.text('ייבוא תיקייה'), findsNothing);
  });

  testWidgets('מחיקת ספר מוחקת את הקובץ ומפעילה סריקה (prune)', (tester) async {
    service.fileNames.add('ספר למחיקה.txt');
    final syncCalls = <List<CustomFolder>>[];
    final bloc = buildBloc(folderRegistered: true, syncCalls: syncCalls);

    await pumpPanel(tester, bloc: bloc);
    await tester.tap(find.text('הספרים שלי'));
    await settle(tester);

    await tester.tap(find.byTooltip('מחק ספר'));
    await settle(tester);
    await tester.tap(find.text('מחק'));
    await settle(tester);

    expect(service.fileNames, isEmpty);
    expect(syncCalls, hasLength(1));
    expect(find.text('ספר למחיקה'), findsNothing);
  });
}

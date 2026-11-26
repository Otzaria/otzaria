import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/panels/custom_folders_panel.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:path/path.dart' as p;

import '../../test_helpers/memory_cache_provider.dart';

/// "נקה הכל" בהגדרות הייבוא כבוי כשאין נתונים מיובאים למחוק (issue #4275).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomFoldersBloc bloc;
  final previousDataRoot = AppPaths.cachedDataRootPath;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_import_tile');
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));
    // תור הפעולות הסטטי נוצר כאן ולא בבניית הווידג'ט: אחרת ה-Future שבראשו
    // שייך ל-FakeAsync של testWidgets, והמתנה לו ב-runAsync נתקעת.
    expect(DatabaseLibraryProvider.operationQueue.isBusy, isFalse);
    bloc = CustomFoldersBloc(addLibraryEvent: (_) {});
  });

  tearDown(() async {
    await bloc.close();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await tempDir.delete(recursive: true);
  });

  VoidCallback? clearAll(WidgetTester tester) => tester
      .widget<ActionButton>(
        find.widgetWithText(ActionButton, 'נקה הכל', skipOffstage: false),
      )
      .onPressed;

  /// מריץ את ה-IO האמיתי מחוץ ל-FakeAsync עד שהבלוק נח.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  /// שולח פעולה שכותבת ב-isolate וממתין לסיומה, לא לפרק זמן קבוע.
  Future<void> runUntilIdle(WidgetTester tester, CustomFoldersEvent e) async {
    await tester.runAsync(() async {
      final idle = bloc.stream.firstWhere((s) => !s.isSyncing);
      bloc.add(e);
      await idle;
    });
    await tester.pump();
  }

  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: BlocProvider.value(
              value: bloc,
              child: const SingleChildScrollView(
                child: UserContentImportTile(),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> importGenerations(WidgetTester tester) async {
    final path = await tester.runAsync(
      () async => (await File(
        p.join(tempDir.path, 'דורות.csv'),
      ).writeAsString('ספר,דור,מחבר\n')).path,
    );
    await runUntilIdle(tester, ImportUserContentFiles([path!]));
  }

  testWidgets('אין נתונים מיובאים — "נקה הכל" כבוי', (tester) async {
    await pumpTile(tester);
    expect(clearAll(tester), isNull);
  });

  testWidgets('אחרי ייבוא "נקה הכל" פעיל, ואחרי הניקוי חוזר לכבוי', (
    tester,
  ) async {
    await pumpTile(tester);
    await importGenerations(tester);
    expect(bloc.state.isSyncing, isFalse);
    expect(clearAll(tester), isNotNull);

    await runUntilIdle(tester, const ClearUserContent());
    expect(clearAll(tester), isNull);
  });

  testWidgets('נתונים ידניים מלפני ספריית הקבצים — "נקה הכל" פעיל', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final raw = await (await UserBooksDatabaseHolder.instance.repository)
          .database
          .database;
      raw.execute("INSERT INTO author (name) VALUES ('רש\"י')");
    });
    await pumpTile(tester);
    expect(clearAll(tester), isNotNull);
  });

  testWidgets('בזמן סנכרון "נקה הכל" כבוי גם כשיש נתונים', (tester) async {
    await pumpTile(tester);
    await importGenerations(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(bloc.state.copyWith(isSyncing: true));
    // הראשון מוסר את המצב מהזרם, השני בונה איתו.
    await tester.pump();
    await tester.pump();
    expect(clearAll(tester), isNull);
  });

  test('ייבוא דרך bloc בחלון אחר מרענן את מצב התוכן', () async {
    final otherWindowBloc = CustomFoldersBloc(addLibraryEvent: (_) {});
    addTearDown(otherWindowBloc.close);
    final refreshed = bloc.stream.firstWhere((s) => s.hasUserContent);
    bloc.add(const LoadUserImportFiles());
    await Future<void>.delayed(Duration.zero);

    final path = File(p.join(tempDir.path, 'דורות.csv'));
    await path.writeAsString('ספר,דור,מחבר\n');
    final imported = otherWindowBloc.stream.firstWhere(
      (s) => s.hasUserContent,
    );
    otherWindowBloc.add(ImportUserContentFiles([path.path]));
    await imported.timeout(const Duration(seconds: 20));
    await refreshed.timeout(const Duration(seconds: 5));

    expect(otherWindowBloc.state.hasUserContent, isTrue);
    expect(bloc.state.hasUserContent, isTrue);
  });
}

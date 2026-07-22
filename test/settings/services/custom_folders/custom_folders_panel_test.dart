import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/panels/custom_folders_panel.dart';

import '../../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const folderPath = 'C:/personal-books';

  setUp(() => Settings.init(cacheProvider: MemorySettingsCache()));

  CustomFoldersBloc buildBloc() {
    return CustomFoldersBloc(
      addLibraryEvent: (_) {},
      loadFolders: () => [
        CustomFolder(
          path: folderPath,
          addToDatabase: true,
          addedAt: DateTime(2026, 5, 7),
        ),
      ],
      saveFolders: (_) async {},
      syncFolders: (_, {String? onlyFolderPath}) async =>
          const FileSyncResult(),
      deleteFolderFromDb: (_) async {},
    )..add(const LoadCustomFolders());
  }

  Future<void> pumpTile(WidgetTester tester, CustomFoldersBloc bloc) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: bloc,
            child: const SingleChildScrollView(child: CustomFoldersPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // פתיחת ה-ExpandableSection כדי לחשוף את שורות התיקיות.
    await tester.tap(find.text('הוסף תיקייה').first);
    await tester.pumpAndSettle();
  }

  Future<void> openFolderMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
    await tester.pumpAndSettle();
  }

  testWidgets('שורת התיקייה מציגה כפתור תפריט ולא כפתור מחיקה ישיר',
      (tester) async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    await pumpTile(tester, bloc);

    // כפתור התפריט מוצג; אין אייקון מחיקה גלוי לפני פתיחת התפריט.
    expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.delete_24_regular), findsNothing);
  });

  testWidgets('התפריט מכיל פתח תיקייה, העתק נתיב והסר תיקייה', (tester) async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    await pumpTile(tester, bloc);
    await openFolderMenu(tester);

    expect(find.text('פתח תיקייה'), findsOneWidget);
    expect(find.text('העתק נתיב'), findsOneWidget);
    expect(find.text('הסר תיקייה'), findsOneWidget);
  });

  testWidgets('בחירת "העתק נתיב" מעתיקה את נתיב התיקייה ללוח', (tester) async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpTile(tester, bloc);
    await openFolderMenu(tester);

    await tester.tap(find.text('העתק נתיב'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, folderPath);
  });

  testWidgets('בחירת "הסר תיקייה" פותחת דיאלוג אישור הסרה', (tester) async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    await pumpTile(tester, bloc);
    await openFolderMenu(tester);

    await tester.tap(find.text('הסר תיקייה'));
    await tester.pumpAndSettle();

    expect(find.text('הסרת תיקייה'), findsOneWidget);
  });
}

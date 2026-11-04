import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/panels/custom_folders_panel.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria/widgets/text/app_section_label.dart';

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

  testWidgets('שורת התיקייה מציגה כפתור תפריט ולא כפתור מחיקה ישיר', (
    tester,
  ) async {
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
    expect(find.text('הסתר מהספרייה'), findsOneWidget);
  });

  testWidgets('"הסתר מהספרייה" מסתיר, מסמן בשורה ומתחלף ל"הצג בספרייה"', (
    tester,
  ) async {
    var folders = [
      CustomFolder(path: folderPath, addedAt: DateTime(2026, 5, 7)),
    ];
    final bloc = CustomFoldersBloc(
      addLibraryEvent: (_) {},
      loadFolders: () => folders,
      saveFolders: (saved) async => folders = saved,
      syncFolders: (_, {String? onlyFolderPath}) async =>
          const FileSyncResult(),
      deleteFolderFromDb: (_) async {},
    )..add(const LoadCustomFolders());
    addTearDown(bloc.close);

    await pumpTile(tester, bloc);
    await openFolderMenu(tester);
    await tester.tap(find.text('הסתר מהספרייה'));
    await tester.pumpAndSettle();

    expect(folders.single.hidden, isTrue);
    expect(find.textContaining('מוסתרת'), findsOneWidget);

    await openFolderMenu(tester);
    expect(find.text('הצג בספרייה'), findsOneWidget);
    await tester.tap(find.text('הצג בספרייה'));
    await tester.pumpAndSettle();

    expect(folders.single.hidden, isFalse);
    expect(find.textContaining('מוסתרת'), findsNothing);
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
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

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

  group('דיאלוג "הצגה או הוספה של הקבצים"', () {
    Future<void> openInfo(WidgetTester tester) async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      await pumpTile(tester, bloc);
      await tester.tap(find.byTooltip('מידע נוסף'));
      await tester.pumpAndSettle();
    }

    testWidgets('מסגרת medium שגוללת בתוך ריפוד הדיאלוג', (tester) async {
      await openInfo(tester);

      final frame = tester.widget<AppDialogFrame>(find.byType(AppDialogFrame));
      expect(frame.title, 'הצגה או הוספה של הקבצים');
      expect(frame.size, AppDialogSize.medium);
      expect(frame.scrollable, isTrue);
      expect(frame.padding, AppTokens.dialogPadding);
      expect(find.byType(AppDialogIconBadge), findsOneWidget);
      // חמשת הפריטים בתוך הגלילה של המסגרת, ולא בגלילה פנימית משלהם.
      final body = find.byType(PanelScrollableContent);
      expect(body, findsOneWidget);
      expect(
        find.descendant(of: body, matching: find.byType(Scrollable)),
        findsOneWidget,
      );
    });

    // הערת בעל הפרויקט 4.11: שני מקטעים עם כותרת. בסקירה השנייה: "יותר
    // אהבתי ... שכמעט כל החלק הפנימי בהיר" — בלי כרטיסים ובלי גוף כהה, רק
    // הכותרות וקו דק בין המקטעים.
    testWidgets('שני מקטעים עם כותרת וקו ביניהם, על גוף הדיאלוג הבהיר', (
      tester,
    ) async {
      await openInfo(tester);

      final dialog = find.byType(AppDialogFrame);
      final labels = find.descendant(
        of: dialog,
        matching: find.byType(AppSectionLabel),
      );
      expect(
        tester.widgetList<AppSectionLabel>(labels).map((l) => l.text),
        ['הספרים שבתיקייה', 'נתונים נוספים'],
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(AppCard)),
        findsNothing,
      );
      expect(
        tester.widget<AppDialogFrame>(dialog).backgroundColor,
        isNull,
        reason: 'גוון הדיאלוג, כמו בכל דיאלוג הסבר',
      );

      // הקו בין שני המקטעים: מתחת לפריט האחרון של הראשון, מעל הכותרת השנייה.
      final divider = find.descendant(
        of: dialog,
        matching: find.byType(Divider),
      );
      expect(divider, findsOneWidget);
      final line = tester.getRect(divider);
      expect(
        line.top,
        greaterThan(tester.getRect(find.text('קבצים שאינם טקסט')).bottom),
      );
      expect(line.bottom, lessThanOrEqualTo(tester.getRect(labels.last).top));
    });

    testWidgets('פריט: אייקון iconMD, כותרת titleSmall והסבר bodyMedium', (
      tester,
    ) async {
      await openInfo(tester);

      final theme = Theme.of(tester.element(find.byType(AppDialogFrame)));
      final title = tester.widget<Text>(find.text('קבצים שאינם טקסט'));
      expect(title.style, theme.textTheme.titleSmall);
      final description = tester.widget<Text>(
        find.textContaining('אין אפשרות להוספה'),
      );
      expect(description.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
      expect(description.style?.color, theme.colorScheme.onSurfaceVariant);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(AppDialogFrame),
          matching: find.byIcon(FluentIcons.database_24_regular),
        ),
      );
      expect(icon.size, AppTokens.iconMD);
    });

    testWidgets('הטקסט אינו נכנס לשוליים שבהם יושב פס הגלילה', (tester) async {
      await openInfo(tester);

      final body = tester.getRect(find.byType(PanelScrollableContent));
      final inset = AppTokens.dialogPadding.horizontal / 2;
      final texts = find.descendant(
        of: find.byType(PanelScrollableContent),
        matching: find.byType(Text),
      );
      // שתי כותרות מקטע, וכותרת והסבר לכל אחד מחמשת הפריטים.
      expect(texts, findsNWidgets(12));
      for (final element in texts.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.left, greaterThanOrEqualTo(body.left + inset));
        expect(rect.right, lessThanOrEqualTo(body.right - inset));
      }
    });

    testWidgets('"סגור" ו-Escape סוגרים את הדיאלוג', (tester) async {
      await openInfo(tester);
      await tester.tap(find.text('סגור'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialogFrame), findsNothing);

      await tester.tap(find.byTooltip('מידע נוסף'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialogFrame), findsNothing);
    });
  });
}

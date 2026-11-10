import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/panels/custom_folders_panel.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
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

  group('כפתורי הכרטיס', () {
    testWidgets('מידע נוסף וסריקה מחדש הם AppIconButton עם tooltip', (
      tester,
    ) async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      await pumpTile(tester, bloc);

      for (final tooltip in ['מידע נוסף', 'סרוק מחדש תיקיות אישיות']) {
        final button = find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(AppIconButton),
        );
        expect(button, findsOneWidget, reason: tooltip);
        expect(
          tester.widget<AppIconButton>(button).size,
          AppIconButtonSize.small,
        );
      }
    });

    testWidgets('בזמן סריקה הכפתור מושבת ומציג LoadingIndicator של הקטלוג', (
      tester,
    ) async {
      final sync = Completer<FileSyncResult>();
      final bloc = CustomFoldersBloc(
        addLibraryEvent: (_) {},
        loadFolders: () => [
          CustomFolder(path: folderPath, addedAt: DateTime(2026, 5, 7)),
        ],
        saveFolders: (_) async {},
        syncFolders: (_, {String? onlyFolderPath}) => sync.future,
        deleteFolderFromDb: (_) async {},
      )..add(const LoadCustomFolders());
      addTearDown(bloc.close);
      await pumpTile(tester, bloc);

      await tester.tap(find.byTooltip('סרוק מחדש תיקיות אישיות'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final button = find.ancestor(
        of: find.byTooltip('סרוק מחדש תיקיות אישיות'),
        matching: find.byType(AppIconButton),
      );
      expect(tester.widget<AppIconButton>(button).onPressed, isNull);
      final spinner = find.descendant(
        of: button,
        matching: find.byType(LoadingIndicator),
      );
      expect(spinner, findsOneWidget);
      expect(
        tester.getSize(spinner),
        const Size.square(LoadingIndicator.inlineSize),
      );

      sync.complete(const FileSyncResult());
      await tester.pumpAndSettle();
    });
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

    // הערת בעל הפרויקט 10.11: "למה הדיאלוג הזה בצבע משעמם בלי כרטיסים
    // לבנים". כל מקטע הוא SettingsCard, כמו בדיאלוג "שינוי מיקום": כותרת,
    // ומתחתיה השורות בכרטיס על גוף הדיאלוג.
    testWidgets('כל מקטע: כותרת, ומתחתיה השורות בכרטיס על גוף הדיאלוג', (
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
      final sections = find.descendant(
        of: dialog,
        matching: find.byType(SettingsCard),
      );
      expect(sections, findsNWidgets(2));
      final cards = find.descendant(
        of: dialog,
        matching: find.byType(AppCard),
      );
      expect(cards, findsNWidgets(2));
      // שורה לכל פריט, כדי שהמפריד של AppCard.section יופיע ביניהן.
      expect(
        tester.widgetList<AppCard>(cards).map((c) => c.children?.length),
        [3, 2],
      );
      expect(
        find.descendant(
          of: cards.first,
          matching: find.text('קבצים שאינם טקסט'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cards.last, matching: find.text('מוסיף קישורים.')),
        findsOneWidget,
      );
      expect(
        tester.getRect(labels.last).top,
        greaterThan(tester.getRect(cards.first).bottom),
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(Divider)),
        findsNothing,
      );
      expect(
        tester.widget<AppDialogFrame>(dialog).backgroundColor,
        isNull,
        reason: 'גוון הדיאלוג, כמו בכל דיאלוג הסבר',
      );

      // הטקסט והאייקון בתוך הכרטיס, לא צמודים למסגרת.
      final card = tester.getRect(cards.first);
      final icon = tester.getRect(
        find.descendant(
          of: cards.first,
          matching: find.byIcon(FluentIcons.document_24_regular),
        ),
      );
      expect(icon.left - card.left, greaterThanOrEqualTo(AppTokens.spaceMD));
      expect(icon.top - card.top, greaterThanOrEqualTo(AppTokens.spaceSMD));
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
      // שתי כותרות מקטע, כותרת והסבר לכל אחד מחמשת הפריטים, וקובץ בכל שורה:
      // שלושה תיאורים וארבעה שמות.
      expect(texts, findsNWidgets(19));
      for (final element in texts.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.left, greaterThanOrEqualTo(body.left + inset));
        expect(rect.right, lessThanOrEqualTo(body.right - inset));
      }
    });

    // שמות הקבצים הם טקסט LTR בתוך פסקה עברית. בלי בידוד, שם עם כמה מקטעים
    // עבריים ("<שם הספר>.כותרות.csv") מצויר בסדר הפוך, והנקודות והסוגריים
    // עוברים למקום שגוי.
    group('שמות הקבצים', () {
      final rli = String.fromCharCode(0x2067);
      final pdi = String.fromCharCode(0x2069);

      Finder fileNameTexts() => find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.textDirection == TextDirection.ltr &&
            (w.data ?? '').contains(RegExp(r'\.(csv|json)')),
        description: 'Text עם שם קובץ LTR',
      );

      testWidgets('כל שם קובץ מוצג כיחידת LTR משלו, ולא בתוך פסקה', (
        tester,
      ) async {
        await openInfo(tester);

        final names = tester
            .widgetList<Text>(fileNameTexts())
            .map((t) => t.data!.replaceAll(rli, '').replaceAll(pdi, ''))
            .toList();
        expect(names, [
          '<שם הספר>.כותרות.csv',
          'גרסאות.csv',
          '<שם הספר>.links.csv',
          '<שם הספר>_links.json',
        ]);

        // אף פסקת הסבר אינה נושאת שם קובץ בתוכה.
        final texts = tester.widgetList<Text>(
          find.descendant(
            of: find.byType(PanelScrollableContent),
            matching: find.byType(Text),
          ),
        );
        for (final text in texts) {
          if (text.textDirection == TextDirection.ltr) continue;
          expect(text.data, isNot(contains('_links.json')));
          expect(text.data, isNot(contains('.links.csv')));
          expect(text.data, isNot(contains('גרסאות.csv')));
        }
      });

      testWidgets('כל רצף עברית בשם קובץ מבודד, והסדר החזותי הוא הלוגי', (
        tester,
      ) async {
        await openInfo(tester);

        final name = tester
            .widgetList<Text>(fileNameTexts())
            .map((t) => t.data!)
            .firstWhere((data) => data.contains('כותרות'));
        expect(name, '<$rliשם הספר$pdi>.$rliכותרות$pdi.csv');
        expect(
          tester.widget<Text>(find.text(name)).style?.fontFamily,
          AppTextStyles.monospaceFamily,
        );

        // "שם הספר" משמאל ל"כותרות", ואחריו הסיומת, כמו בקריאה משמאל לימין.
        final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
        double leftOf(String word) {
          final start = name.indexOf(word);
          return paragraph
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: start,
                  extentOffset: start + word.length,
                ),
              )
              .first
              .left;
        }

        expect(leftOf('שם הספר'), lessThan(leftOf('כותרות')));
        expect(leftOf('כותרות'), lessThan(leftOf('csv')));
      });

      testWidgets('שם הקובץ בשורה משלו, ומתחתיו מה שהקובץ עושה', (
        tester,
      ) async {
        await openInfo(tester);

        final names = fileNameTexts();
        final headings = tester.getRect(names.first);
        final description = tester.getRect(
          find.textContaining('ליד ספר טקסט: מוסיף לו את לשונית'),
        );
        expect(description.top, greaterThanOrEqualTo(headings.bottom));

        // שני שמות הקישורים זה מתחת לזה, ותיאור אחד מתחתם.
        final links = tester.getRect(names.at(2));
        final linksJson = tester.getRect(names.at(3));
        expect(linksJson.top, greaterThanOrEqualTo(links.bottom));
        expect(
          tester.getRect(find.text('מוסיף קישורים.')).top,
          greaterThanOrEqualTo(linksJson.bottom),
        );

        // השם בתחילת השורה, באותו קו עם הכותרת שמעליו (בבדיקה הכיוון LTR).
        final title = tester.getRect(
          find.text('קישורים, כותרות וגרסאות בתיקייה'),
        );
        expect(headings.left, title.left);
      });
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

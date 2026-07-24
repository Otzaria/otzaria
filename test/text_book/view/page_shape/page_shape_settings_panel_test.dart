// טסטים לתוכן פאנל הגדרות צורת הדף:
// 1. גופן הפאנל מיועד למפרשים התחתונים בלבד (התווית "גופן מפרשים תחתונים:"),
//    והמפרשים הצדדיים נשארים עם גופן המפרשים הגלובלי.
// 2. עדכון חי: כל שינוי (גופן, גודל, הדגשה) נשמר מיידית ומפעיל את
//    onSettingsChanged כדי שהמסך יתרענן בלי לסגור את הפאנל.
// 3. שדות המפרשים נפתחים כתפריט חיפוש מוצמד (לא דיאלוג): בחירה נשמרת מיידית,
//    "ללא מפרש" ממופה ל-null, "מפרשים מרובים" עובר למצב מרובה, וחיפוש מסנן.
// הפאנל נגלל ע"י ContextOverlayPanel העוטף; כאן עוטפים ב-SingleChildScrollView.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_panel.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    // חימום מטמון הדורות מחוץ ל-FakeAsync של הטסט, כדי ש-splitByEra
    // (הבונה את תפריט המפרשים) יסתיים סינכרונית בתוך הטסט ולא ייתקע על ה-DB.
    await text_utils.splitByEra(const []);
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    VoidCallback? onSettingsChanged,
    String? currentWorkspaceId,
    List<String> availableCommentators = const ['רש"י על בראשית'],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: PageShapeSettingsPanel(
                availableCommentators: availableCommentators,
                bookTitle: 'בראשית',
                currentWorkspaceId: currentWorkspaceId,
                onSettingsChanged: onSettingsChanged,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // פריט מתוך תפריט החיפוש המוצמד בלבד (Material עם elevation 8), כדי
  // להבחין בינו לבין השדות הסגורים שמציגים את אותה תווית.
  Finder menuItem(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is Material && w.elevation == 8),
    matching: find.text(label),
  );

  testWidgets('תווית הגופן מסייגת שהוא למפרשים התחתונים בלבד', (tester) async {
    await pumpPanel(tester);

    expect(find.text('גופן מפרשים תחתונים:'), findsOneWidget);
  });

  testWidgets('ללא בחירה שמורה - מוצג גופן ברירת המחדל', (tester) async {
    await pumpPanel(tester);

    // הדרופדאון הסגור מציג את התווית העברית של AppFonts.defaultFont
    expect(find.text('פרנק-רוהל'), findsOneWidget);
  });

  testWidgets('תחום שמירת התצוגה מוצג כשלוש בחירות', (tester) async {
    await pumpPanel(tester, currentWorkspaceId: 'workspace-1');

    expect(find.text('ספר זה'), findsOneWidget);
    expect(find.text('שולחן עבודה זה'), findsOneWidget);
    expect(find.text('גלובלי'), findsOneWidget);
  });

  testWidgets('בחירת שולחן עבודה שומרת הגדרות תצוגה ל-workspace', (
    tester,
  ) async {
    await pumpPanel(tester, currentWorkspaceId: 'workspace-1');

    await tester.tap(find.text('שולחן עבודה זה'));
    await tester.pump();

    final highlightSwitch = find.widgetWithText(
      SwitchListTile,
      'הדגש פרשנים קשורים',
    );
    await tester.ensureVisible(highlightSwitch);
    await tester.pump();
    await tester.tap(highlightSwitch);
    await tester.pump();

    expect(
      Settings.getValue<bool>('page_shape_use_workspace_settings_workspace-1'),
      isTrue,
    );
    expect(
      Settings.getValue<bool>('page_shape_workspace_highlight_workspace-1'),
      isTrue,
    );
    expect(Settings.getValue<bool>('page_shape_global_highlight'), isNull);
  });

  testWidgets('בחירת גופן נשמרת מיידית ומפעילה עדכון חי', (tester) async {
    var notified = 0;
    await pumpPanel(tester, onSettingsChanged: () => notified++);

    final dropdown = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(dropdown);
    await tester.pump();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    await tester.tap(find.text('כתר').last);
    await tester.pumpAndSettle();

    expect(Settings.getValue<String>('page_shape_bottom_font'), 'KeterYG');
    expect(notified, greaterThan(0));
  });

  testWidgets('הגדלת גודל הגופן נשמרת מיידית ומפעילה עדכון חי', (tester) async {
    var notified = 0;
    await pumpPanel(tester, onSettingsChanged: () => notified++);

    final addButton = find.widgetWithIcon(
      IconButton,
      FluentIcons.add_24_regular,
    );
    await tester.ensureVisible(addButton);
    await tester.pump();
    await tester.tap(addButton);
    await tester.pump();

    // ברירת המחדל 16 + לחיצה אחת = 17
    expect(
      Settings.getValue<double>('page_shape_commentary_font_size'),
      17.0,
    );
    expect(notified, greaterThan(0));
  });

  testWidgets('שינוי הדגשת פרשנים קשורים מפעיל עדכון חי', (tester) async {
    var notified = 0;
    await pumpPanel(tester, onSettingsChanged: () => notified++);

    final highlightSwitch = find.widgetWithText(
      SwitchListTile,
      'הדגש פרשנים קשורים',
    );
    await tester.ensureVisible(highlightSwitch);
    await tester.pump();
    await tester.tap(highlightSwitch);
    await tester.pump();

    expect(Settings.getValue<bool>('page_shape_global_highlight'), isTrue);
    expect(notified, greaterThan(0));
  });

  testWidgets('שדות המפרשים מציגים "ללא מפרש" כברירת מחדל', (tester) async {
    await pumpPanel(tester);
    await tester.pumpAndSettle();

    // ארבעת שדות המפרשים סגורים על "ללא מפרש".
    expect(
      find.widgetWithText(FilledButton, 'ללא מפרש'),
      findsNWidgets(4),
    );
  });

  testWidgets('שדה מפרש נפתח כתפריט חיפוש ובחירה נשמרת מיידית', (tester) async {
    var notified = 0;
    await pumpPanel(tester, onSettingsChanged: () => notified++);
    // המתנה לטעינת הדורות (splitByEra אסינכרוני) כדי שהתפריט יאוכלס.
    await tester.pumpAndSettle();

    // "מפרש ימני" הוא השדה הראשון — פותחים אותו.
    final field = find.widgetWithText(FilledButton, 'ללא מפרש').first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();

    // תפריט החיפוש המוצמד נפתח.
    expect(find.text('חיפוש מפרש...'), findsOneWidget);

    // בחירת המפרש הזמין מתוך התפריט.
    await tester.tap(find.text('רש"י על בראשית').last);
    await tester.pumpAndSettle();

    // השדה הסגור מציג כעת את המפרש שנבחר, והעדכון החי הופעל.
    expect(
      find.widgetWithText(FilledButton, 'רש"י על בראשית'),
      findsOneWidget,
    );
    expect(notified, greaterThan(0));
  });

  testWidgets('בחירת "ללא מפרש" בשדה ממפה ל-null ונשמרת', (tester) async {
    await pumpPanel(tester);
    await tester.pumpAndSettle();

    // תחילה בוחרים מפרש אמיתי בשדה הימני כדי שיהיה מה לאפס.
    final field = find.widgetWithText(FilledButton, 'ללא מפרש').first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(menuItem('רש"י על בראשית'));
    await tester.pumpAndSettle();

    expect(
      PageShapeSettingsManager.loadConfiguration('בראשית')?['left'],
      'רש"י על בראשית',
    );

    // חוזרים ובוחרים "ללא מפרש" → הערך הנשמר חוזר ל-null.
    await tester.tap(find.widgetWithText(FilledButton, 'רש"י על בראשית'));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('ללא מפרש'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'ללא מפרש'), findsNWidgets(4));
    expect(
      PageShapeSettingsManager.loadConfiguration('בראשית')?['left'],
      isNull,
    );
  });

  testWidgets(
    'בחירת "מפרשים מרובים" בשדה השמאלי עוברת למצב מרובה ומציגה את פאנל המידע',
    (tester) async {
      await pumpPanel(tester);
      await tester.pumpAndSettle();

      // "מפרש שמאלי" הוא השדה היחיד שמציע את מצב הבחירה המרובה.
      final leftPaneField = find.descendant(
        of: find
            .ancestor(of: find.text('מפרש שמאלי'), matching: find.byType(Row))
            .first,
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(leftPaneField);
      await tester.pumpAndSettle();
      await tester.tap(leftPaneField);
      await tester.pumpAndSettle();

      await tester.tap(menuItem('מפרשים מרובים'));
      await tester.pumpAndSettle();

      // מצב מרובה נכנס לתוקף → _buildRightPaneInfo מוצג.
      expect(
        find.text('הבחירה המפורטת נעשית מתוך החלונית עצמה.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('הקלדה בשדה החיפוש מסננת את רשימת המפרשים בתפריט', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      availableCommentators: const [
        'רש"י על בראשית',
        'רמב"ן על בראשית',
        'ספורנו על בראשית',
      ],
    );
    await tester.pumpAndSettle();

    final field = find.widgetWithText(FilledButton, 'ללא מפרש').first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();

    // לפני סינון — שלושת המפרשים מופיעים בתפריט.
    expect(menuItem('רש"י על בראשית'), findsOneWidget);
    expect(menuItem('רמב"ן על בראשית'), findsOneWidget);
    expect(menuItem('ספורנו על בראשית'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'רמב');
    await tester.pumpAndSettle();

    // אחרי סינון — רק המפרש התואם נשאר.
    expect(menuItem('רמב"ן על בראשית'), findsOneWidget);
    expect(menuItem('רש"י על בראשית'), findsNothing);
    expect(menuItem('ספורנו על בראשית'), findsNothing);
  });
}

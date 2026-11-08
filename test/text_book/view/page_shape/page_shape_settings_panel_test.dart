// הפאנל נגלל ב-ContextOverlayPanel; כאן נדרשת מעטפת גלילה מקבילה.

import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_commentary_font_slider.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_panel.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

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
    SettingsLanguage language = SettingsLanguage.hebrew,
    VoidCallback? onSettingsChanged,
    String? currentWorkspaceId,
    String? currentLeft,
    String? currentRight,
    String? currentBottom,
    String? currentBottomRight,
    String? heCategories,
    List<String> availableCommentators = const ['רש"י על בראשית'],
  }) async {
    await tester.pumpWidget(
      SettingsTextScope(
        language: language,
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: PageShapeSettingsPanel(
                  availableCommentators: availableCommentators,
                  bookTitle: 'בראשית',
                  heCategories: heCategories,
                  currentWorkspaceId: currentWorkspaceId,
                  currentLeft: currentLeft,
                  currentRight: currentRight,
                  currentBottom: currentBottom,
                  currentBottomRight: currentBottomRight,
                  onSettingsChanged: onSettingsChanged,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // פריט מתוך תפריט החיפוש המוצמד בלבד (Material בהגבהה של תפריט,
  // AppTokens.elevation2 לפי DD-12), כדי להבחין בינו לבין השדות הסגורים
  // שמציגים את אותה תווית.
  Finder menuItem(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is Material && w.elevation == AppTokens.elevation2,
    ),
    matching: find.text(label),
  );

  List<AppDropdownField<String>> commentatorFields(WidgetTester tester) => [
    for (final label in [
      'מפרש ימני',
      'מפרש שמאלי',
      'מפרש תחתון',
      'מפרש תחתון נוסף',
    ])
      tester.widget<AppDropdownField<String>>(
        find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Row))
              .first,
          matching: find.byType(AppDropdownField<String>),
        ),
      ),
  ];

  testWidgets('פאנל פתוח מתעדכן בכל ארבע הבחירות ושומר ערכים גלויים בלבד', (
    tester,
  ) async {
    const hidden = 'מפרש מוסתר';
    const visible = 'מפרש גלוי';
    await pumpPanel(
      tester,
      currentLeft: hidden,
      currentRight: hidden,
      currentBottom: hidden,
      currentBottomRight: hidden,
      availableCommentators: const [hidden, visible],
    );
    await tester.pumpAndSettle();
    expect(
      commentatorFields(tester).map((field) => field.value),
      everyElement(hidden),
    );

    await pumpPanel(
      tester,
      availableCommentators: const [visible],
    );
    await tester.pumpAndSettle();
    expect(
      commentatorFields(tester).map((field) => field.value),
      everyElement('__NONE__'),
    );
    expect(
      commentatorFields(tester).first.entries.map((entry) => entry.value),
      isNot(contains(hidden)),
    );

    final visibilityButton = find.byTooltip('הסתר טור').first;
    await tester.ensureVisible(visibilityButton);
    await tester.tap(visibilityButton);
    await tester.pumpAndSettle();
    expect(
      PageShapeSettingsManager.loadConfiguration('בראשית'),
      containsPair('left', null),
    );
    final saved = PageShapeSettingsManager.loadConfiguration('בראשית')!;
    expect(saved['right'], isNull);
    expect(saved['bottom'], isNull);
    expect(saved['bottomRight'], isNull);

    await pumpPanel(
      tester,
      currentLeft: visible,
      currentRight: visible,
      currentBottom: visible,
      currentBottomRight: visible,
      availableCommentators: const [visible],
    );
    await tester.pumpAndSettle();
    expect(
      commentatorFields(tester).map((field) => field.value),
      everyElement(visible),
    );
  });

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

    // "ספר זה" מופיע גם בבורר שמירת המפרשים.
    expect(find.text('ספר זה'), findsNWidgets(2));
    expect(find.text('שולחן עבודה זה'), findsOneWidget);
    expect(find.text('גלובלי'), findsOneWidget);
  });

  testWidgets('בורר שמירת המפרשים מציע שולחן עבודה כשיש שולחן פעיל', (
    tester,
  ) async {
    await pumpPanel(tester, currentWorkspaceId: 'workspace-1');

    expect(find.text('שמירת בחירת מפרשים'), findsOneWidget);
    expect(find.text('ספר זה בשולחן'), findsOneWidget);
  });

  testWidgets(
    'תוויות שמירת המפרשים מציינות שהבחירה לספר הנוכחי (issue #1731)',
    (tester) async {
      await pumpPanel(tester, currentWorkspaceId: 'workspace-1');

      // "שולחן עבודה" לבדו נקרא כמו "שולחן עבודה זה" שבבורר התצוגה (כל ספרי
      // השולחן), בעוד שכאן הבחירה היא לספר הנוכחי בשולחן זה בלבד.
      expect(find.text('שולחן עבודה'), findsNothing);
      expect(find.text('ספר'), findsNothing);
    },
  );

  testWidgets('תוויות שמירת המפרשים באנגלית שומרות על היקף הספר', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      language: SettingsLanguage.english,
      currentWorkspaceId: 'workspace-1',
    );

    expect(find.text('This Sefer'), findsOneWidget);
    expect(find.text('Workspace Sefer'), findsOneWidget);
    await tester.tap(find.text('Workspace Sefer'));
    await tester.pumpAndSettle();
    expect(
      PageShapeSettingsManager.loadConfiguration(
        'בראשית',
        workspaceId: 'workspace-1',
      ),
      isNotNull,
    );
    expect(PageShapeSettingsManager.loadConfiguration('בראשית'), isNull);
  });

  testWidgets('בלי שולחן פעיל, בורר שמירת המפרשים אינו מוצג', (tester) async {
    await pumpPanel(tester);

    expect(find.text('ספר זה בשולחן'), findsNothing);
  });

  testWidgets('שמירה בתחום שולחן עבודה אינה דורסת את הגדרת הספר', (
    tester,
  ) async {
    await PageShapeSettingsManager.saveConfiguration('בראשית', {
      'left': 'רש"י על בראשית',
    });

    await pumpPanel(
      tester,
      currentWorkspaceId: 'workspace-1',
      availableCommentators: const ['רש"י על בראשית', 'רמב"ן על בראשית'],
    );

    await tester.tap(find.text('ספר זה בשולחן'));
    await tester.pumpAndSettle();

    expect(
      PageShapeSettingsManager.loadConfiguration(
        'בראשית',
        workspaceId: 'workspace-1',
      ),
      isNotNull,
    );
    expect(
      PageShapeSettingsManager.loadConfiguration('בראשית')?['left'],
      'רש"י על בראשית',
    );
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

    final fontField = find.byType(FontDropdownField);
    await tester.ensureVisible(fontField);
    await tester.pump();
    await tester.tap(fontField);
    await tester.pumpAndSettle();

    await tester.tap(find.text('כתר').last);
    await tester.pumpAndSettle();

    expect(Settings.getValue<String>('page_shape_bottom_font'), 'KeterYG');
    expect(notified, greaterThan(0));
  });

  testWidgets('בחירת קטגוריה נשמרת לקטגוריה ומפעילה עדכון חי', (tester) async {
    var notified = 0;
    await pumpPanel(
      tester,
      heCategories: 'סדר מועד, מסכת שבת',
      onSettingsChanged: () => notified++,
    );

    // מעבר לשמירה בתחום קטגוריה
    await tester.tap(find.text('קטגוריה'));
    await tester.pumpAndSettle();

    // בדיקה ששדה בחירת הקטגוריה מופיע
    expect(find.text('בחר קטגוריה:'), findsOneWidget);

    // פתיחת התפריט ובחירת "מסכת שבת"
    final categoryField = find.widgetWithText(FilledButton, 'סדר מועד');
    await tester.tap(categoryField);
    await tester.pumpAndSettle();

    await tester.tap(find.text('מסכת שבת').last);
    await tester.pumpAndSettle();

    expect(notified, greaterThan(0));
    expect(find.widgetWithText(FilledButton, 'מסכת שבת'), findsOneWidget);
  });

  testWidgets('הגדלת גודל הגופן נשמרת מיידית ומפעילה עדכון חי', (tester) async {
    var notified = 0;
    await pumpPanel(tester, onSettingsChanged: () => notified++);

    final slider = find.descendant(
      of: find.byType(PageShapeCommentaryFontSizeSlider),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    await tester.pump();
    tester.widget<Slider>(slider).onChangeEnd!(17);
    await tester.pump();
    await tester.pump();

    // סוף גרירה מ-16 ל-17
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

  testWidgets('שמירת הגדרה אחרת אינה מוחקת בחירה מרובה מהחלונית', (
    tester,
  ) async {
    final selection = encodePageShapeCommentatorsSelection(
      const ['רש"י על בראשית', 'רמב"ן על בראשית'],
      forceMultipleMode: true,
    );
    await pumpPanel(
      tester,
      currentRight: selection,
      availableCommentators: const ['רש"י על בראשית', 'רמב"ן על בראשית'],
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'רש"י על בראשית'),
      findsOneWidget,
    );

    final highlightSwitch = find.widgetWithText(
      SwitchListTile,
      'הדגש פרשנים קשורים',
    );
    await tester.ensureVisible(highlightSwitch);
    await tester.tap(highlightSwitch);
    await tester.pumpAndSettle();

    expect(
      PageShapeSettingsManager.loadConfiguration('בראשית')?['right'],
      selection,
    );
  });

  testWidgets('השדה השמאלי אינו מציע עוד "מפרשים מרובים"', (tester) async {
    await pumpPanel(tester);
    await tester.pumpAndSettle();

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

    expect(menuItem('מפרשים מרובים'), findsNothing);
    expect(menuItem('ללא מפרש'), findsOneWidget);
    expect(menuItem('רש"י על בראשית'), findsOneWidget);
  });

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

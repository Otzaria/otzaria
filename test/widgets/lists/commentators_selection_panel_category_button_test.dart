// כפתור "קבע כמפרשים קבועים לקטגוריה" בפאנל בחירת המפרשים (issue #866):
// מוצג רק כשלספר יש קטגוריות, פותח את הדיאלוג, והאישור שומר את הבחירה
// לקטגוריה ומפעיל את ניקוי הבחירה הפר-ספרית.
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/category_commentators_service.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const groups = [
    CommentatorGroup(title: 'ראשונים', commentators: ['רש"י על ברכות']),
  ];
  const tooltip = 'קבע כמפרשים קבועים לקטגוריה';

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pump(
    WidgetTester tester, {
    String? heCategories,
    List<String> selected = const ['רש"י על ברכות'],
    VoidCallback? onCategoryDefaultsSaved,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CommentatorsSelectionPanel(
              groups: groups,
              selectedCommentators: selected,
              onSelectionChanged: (_) {},
              bookTitle: 'ברכות',
              heCategories: heCategories,
              onCategoryDefaultsSaved: onCategoryDefaultsSaved,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('בלי קטגוריות הכפתור אינו מוצג', (tester) async {
    await pump(tester);

    expect(find.byTooltip(tooltip), findsNothing);
  });

  testWidgets('עם קטגוריות הכפתור מוצג בכותרת הרשימה', (tester) async {
    await pump(tester, heCategories: 'אוצריא, תלמוד, תלמוד בבלי');

    expect(find.byTooltip(tooltip), findsOneWidget);
  });

  testWidgets('אישור הדיאלוג שומר לקטגוריה ומפעיל את ניקוי הפר-ספרי', (
    tester,
  ) async {
    var clearedPerBook = false;
    await pump(
      tester,
      heCategories: 'אוצריא, תלמוד, תלמוד בבלי',
      onCategoryDefaultsSaved: () => clearedPerBook = true,
    );

    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    expect(find.text('מפרשים קבועים לקטגוריה'), findsOneWidget);

    await tester.tap(find.text('קבע'));
    await tester.pumpAndSettle();

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      ['רש"י'],
    );
    expect(clearedPerBook, isTrue);
  });

  testWidgets('ביטול הדיאלוג לא שומר דבר', (tester) async {
    await pump(tester, heCategories: 'אוצריא, תלמוד, תלמוד בבלי');

    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      isNull,
    );
  });

  testWidgets('כשקיימת קביעה מוצג "הסר קביעה קיימת" והוא מסיר אותה', (
    tester,
  ) async {
    await CategoryCommentatorsService.save(
      'תלמוד בבלי',
      ['רש"י על ברכות'],
      bookTitle: 'ברכות',
    );
    await pump(tester, heCategories: 'אוצריא, תלמוד, תלמוד בבלי');

    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הסר קביעה קיימת'));
    await tester.pumpAndSettle();

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      isNull,
    );
  });
}

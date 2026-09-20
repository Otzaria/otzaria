import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/search/settings_search_field.dart';
import 'package:otzaria/settings/search/settings_search_results_view.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// האייקון בשדה החיפוש של ההגדרות מוצג ב-18 פיקסלים. גלגל שיניים בתוך עדשת
/// הזכוכית המגדלת נמרח שם לכתם (issue #1205), ולכן שם מוצגת זכוכית פשוטה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );

  testWidgets('שדה החיפוש בהגדרות מציג זכוכית מגדלת פשוטה (issue #1205)', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(SettingsSearchField(controller: controller, onChanged: (_) {})),
    );
    await tester.pump();

    final icons = tester
        .widgetList<Icon>(
          find.descendant(
            of: find.byType(SettingsSearchField),
            matching: find.byType(Icon),
          ),
        )
        .toList();

    expect(icons, hasLength(1), reason: 'בשדה ריק יש רק אייקון הקידומת');
    expect(icons.single.icon, OtzariaIcons.search_24_regular);
    expect(
      icons.single.size,
      lessThanOrEqualTo(20.0),
      reason: 'בגודל כזה פרט פנימי באייקון אינו קריא',
    );
  });

  testWidgets('מצב "לא נמצאו הגדרות" נשאר עם אייקון ההגדרות (issue #1205)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        SettingsSearchResultsView(
          results: const <SettingsSearchEntry>[],
          query: 'אין כזה',
          onResultTap: (_) {},
        ),
      ),
    );
    await tester.pump();

    // שם האייקון מוצג ב-56 פיקסלים, גלגל השיניים קריא והוא נושא משמעות.
    final emptyState = tester.widget<OtzariaEmptyState>(
      find.byType(OtzariaEmptyState),
    );
    expect(emptyState.icon, OtzariaIcons.search_in_the_settings_24_regular);
  });
}

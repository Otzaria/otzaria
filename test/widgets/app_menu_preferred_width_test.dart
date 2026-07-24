import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// בודק את `calculateAppMenuPreferredWidth` — הפונקציה המשותפת שקובעת גם
/// את רוחב התפריט הנפתח וגם את רוחב הכפתור הפותח אותו (AppDropdownField).
void main() {
  final metrics = AppMenuMetrics.create(compactMenus: false);

  testWidgets('רשימה ריקה מחזירה את רוחב המינימום של התפריט', (tester) async {
    final width = calculateAppMenuPreferredWidth<int>(metrics, const []);
    expect(width, metrics.menuMinWidth);
  });

  testWidgets('תווית ארוכה יותר דורשת רוחב גדול יותר', (tester) async {
    final shortWidth = calculateAppMenuPreferredWidth<int>(
      metrics,
      const [AppMenuEntry<int>(value: 1, label: 'א')],
    );
    final longWidth = calculateAppMenuPreferredWidth<int>(
      metrics,
      const [
        AppMenuEntry<int>(
          value: 1,
          label: 'תווית ארוכה משמעותית יותר מהקודמת בהרבה',
        ),
      ],
    );

    expect(longWidth, greaterThan(shortWidth));
  });

  testWidgets('משוריין מקום לסימן ה-✓ גם לפריט יחיד לא נבחר', (tester) async {
    // הפריט עדיין עלול להיבחר בעתיד, ולכן חובה לשריין לו מקום מראש.
    const label = 'תווית לבדיקה';
    final width = calculateAppMenuPreferredWidth<int>(
      metrics,
      const [AppMenuEntry<int>(value: 1, label: label)],
    );

    // הרוחב חייב להיות גדול משמעותית מ-menuMinWidth בלבד + padding,
    // כלומר כולל גם את מקום סימן ה-✓ (iconSize + checkmark gap).
    final withoutCheckmarkReservation =
        metrics.itemPadding.horizontal; // רק ריפוד, בלי אף slot
    expect(width, greaterThan(withoutCheckmarkReservation + metrics.iconSize));
  });

  testWidgets('פריט עם אייקון מוביל דורש רוחב גדול יותר מפריט זהה בלי אייקון', (
    tester,
  ) async {
    const label = 'תווית זהה';
    final withoutIcon = calculateAppMenuPreferredWidth<int>(
      metrics,
      const [AppMenuEntry<int>(value: 1, label: label)],
    );
    final withIcon = calculateAppMenuPreferredWidth<int>(
      metrics,
      const [
        AppMenuEntry<int>(
          value: 1,
          label: label,
          icon: FluentIcons.book_24_regular,
        ),
      ],
    );

    expect(withIcon, greaterThan(withoutIcon));
  });
}

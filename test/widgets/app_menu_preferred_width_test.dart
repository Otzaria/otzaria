import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
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

  testWidgets('רשימת ענק נמדדת במנות ושומרת על הרוחב המרבי', (tester) async {
    const longest = 'כותרת ארוכה מאוד שנמצאת בסוף רשימה של עשרות אלפי שורות';
    final entries = [
      for (var i = 0; i < 60000; i++)
        AppMenuEntry<int>(value: i, label: 'שורה ${i + 1}'),
      const AppMenuEntry<int>(value: -1, label: longest),
    ];

    var individualMaxWidth = 0.0;
    for (final entry in entries) {
      final painter = TextPainter(
        text: TextSpan(
          text: entry.label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: metrics.fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      if (painter.width > individualMaxWidth) {
        individualMaxWidth = painter.width;
      }
      painter.dispose();
    }
    expect(individualMaxWidth, greaterThan(0));

    var painterCount = 0;
    void countPainter(ObjectEvent event) {
      if (event is ObjectCreated && event.object is TextPainter) painterCount++;
    }

    late final double width;
    FlutterMemoryAllocations.instance.addListener(countPainter);
    try {
      width = calculateAppMenuPreferredWidth<int>(metrics, entries);
    } finally {
      FlutterMemoryAllocations.instance.removeListener(countPainter);
    }

    final longestOnly = calculateAppMenuPreferredWidth<int>(metrics, const [
      AppMenuEntry<int>(value: -1, label: longest),
    ]);
    expect(width, longestOnly);
    final labelWidth =
        width - metrics.itemPadding.horizontal - metrics.iconSize - 4;
    expect(labelWidth, greaterThanOrEqualTo(individualMaxWidth));
    expect(labelWidth - individualMaxWidth, lessThanOrEqualTo(2));
    expect(painterCount, greaterThan(0));
    expect(
      painterCount,
      lessThan(entries.length / 10),
      reason: 'המדידה חייבת לחסוך יצירת TextPainter לכל תווית',
    );
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
          icon: OtzariaIcons.book_24_regular,
        ),
      ],
    );

    expect(withIcon, greaterThan(withoutIcon));
  });
}

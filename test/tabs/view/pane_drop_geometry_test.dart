import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';

/// חלוקת אזור הקריאה לשני חצאים: לאיזה צד ייכנס הספר הנגרר, ומה מוצג
/// כתצוגה מקדימה.
void main() {
  const size = Size(1000, 600);

  PaneDropSide sideAt(double dx, TextDirection direction) => dropSideFor(
    localPosition: Offset(dx, 300),
    size: size,
    textDirection: direction,
  );

  group('בחירת הצד ב-RTL', () {
    test('החצי הימני הוא החלונית הראשונה', () {
      expect(sideAt(900, TextDirection.rtl), PaneDropSide.start);
    });

    test('החצי השמאלי הוא החלונית השנייה', () {
      expect(sideAt(100, TextDirection.rtl), PaneDropSide.end);
    });

    test('קו האמצע עצמו שייך לחלונית הראשונה', () {
      expect(sideAt(500, TextDirection.rtl), PaneDropSide.start);
    });

    test('קצה שמאל וקצה ימין נותנים צדדים הפוכים', () {
      expect(sideAt(0, TextDirection.rtl), PaneDropSide.end);
      expect(sideAt(1000, TextDirection.rtl), PaneDropSide.start);
    });
  });

  group('בחירת הצד ב-LTR', () {
    test('החצי השמאלי הוא החלונית הראשונה', () {
      expect(sideAt(100, TextDirection.ltr), PaneDropSide.start);
    });

    test('החצי הימני הוא החלונית השנייה', () {
      expect(sideAt(900, TextDirection.ltr), PaneDropSide.end);
    });
  });

  test('רוחב אפס אינו מפיל ומחזיר ברירת מחדל', () {
    expect(
      dropSideFor(
        localPosition: Offset.zero,
        size: Size.zero,
        textDirection: TextDirection.rtl,
      ),
      PaneDropSide.start,
    );
  });

  group('מקום מזערי לפיצול', () {
    test('בעכבר כולל את המפריד והשוליים', () {
      const platform = TargetPlatform.windows;
      final minimum = minimumSplitPaneWidthFor(platform);

      expect(minimum, 298);
      expect(canSplitPane(Size(minimum, 600), platform: platform), isTrue);
      expect(
        canSplitPane(Size(minimum - 1, 600), platform: platform),
        isFalse,
      );
    });

    test('במגע כולל רצועת מפריד רחבה יותר', () {
      const platform = TargetPlatform.android;
      final minimum = minimumSplitPaneWidthFor(platform);

      expect(minimum, 310);
      expect(canSplitPane(Size(minimum, 600), platform: platform), isTrue);
      expect(
        canSplitPane(Size(minimum - 1, 600), platform: platform),
        isFalse,
      );
    });
  });

  group('תצוגה מקדימה', () {
    test('ב-RTL החלונית הראשונה מסומנת בחצי הימני', () {
      final rect = previewRectFor(
        side: PaneDropSide.start,
        size: size,
        textDirection: TextDirection.rtl,
      );

      expect(rect, const Rect.fromLTWH(500, 0, 500, 600));
    });

    test('ב-RTL החלונית השנייה מסומנת בחצי השמאלי', () {
      final rect = previewRectFor(
        side: PaneDropSide.end,
        size: size,
        textDirection: TextDirection.rtl,
      );

      expect(rect, const Rect.fromLTWH(0, 0, 500, 600));
    });

    test('ב-LTR הצדדים מתהפכים', () {
      expect(
        previewRectFor(
          side: PaneDropSide.start,
          size: size,
          textDirection: TextDirection.ltr,
        ),
        const Rect.fromLTWH(0, 0, 500, 600),
      );
      expect(
        previewRectFor(
          side: PaneDropSide.end,
          size: size,
          textDirection: TextDirection.ltr,
        ),
        const Rect.fromLTWH(500, 0, 500, 600),
      );
    });

    test('החיווי תמיד בגובה מלא וברוחב חצי', () {
      for (final side in PaneDropSide.values) {
        final rect = previewRectFor(
          side: side,
          size: size,
          textDirection: TextDirection.rtl,
        );
        expect(rect.height, size.height);
        expect(rect.width, size.width / 2);
      }
    });
  });

  test('בכל נקודה החצי המסומן הוא החצי שהמצביע נמצא בו', () {
    for (final direction in TextDirection.values) {
      for (final dx in [50.0, 300.0, 700.0, 950.0]) {
        final side = sideAt(dx, direction);
        final rect = previewRectFor(
          side: side,
          size: size,
          textDirection: direction,
        );
        expect(
          rect.left <= dx && dx <= rect.right,
          isTrue,
          reason: 'כיוון $direction, x=$dx',
        );
      }
    }
  });
}

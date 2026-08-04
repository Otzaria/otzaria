import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/page_turn_geometry.dart';

void main() {
  const spineX = 400.0;
  const pageWidth = 400.0;
  const height = 600.0;

  PageTurnGeometry compute(double progress, {bool turnLeftPage = true}) =>
      PageTurnGeometry.compute(
        spineX: spineX,
        pageWidth: pageWidth,
        height: height,
        progress: progress,
        turnLeftPage: turnLeftPage,
      );

  group('PageTurnGeometry — קצוות הדפדוף', () {
    test('בתחילת הדפדוף הדף שטוח בצד המקור ומציג את החזית', () {
      final geometry = compute(0.001);

      expect(geometry.minX, closeTo(spineX - pageWidth, 1.0));
      expect(geometry.maxX, closeTo(spineX, 0.01));
      expect(geometry.strips.every((s) => s.showsFront), isTrue);
      expect(geometry.hasBackStrips, isFalse);
      for (final strip in geometry.strips) {
        expect(strip.height, closeTo(height, 1.0));
      }
    });

    test('בסוף הדפדוף הדף נוחת שטוח בצד היעד ומציג את הגב', () {
      final geometry = compute(1.0);

      expect(geometry.minX, closeTo(spineX, 0.01));
      expect(geometry.maxX, closeTo(spineX + pageWidth, 1.0));
      expect(geometry.strips.every((s) => !s.showsFront), isTrue);
      expect(geometry.shadeStrength, closeTo(0.0, 1e-9));
      for (final strip in geometry.strips) {
        expect(strip.height, closeTo(height, 0.01));
        expect(strip.tilt, closeTo(0.0, 0.05));
      }
    });

    test('כיוון הפוך (עמוד ימני) — מראה של תחילת הדפדוף בצד ימין', () {
      final geometry = compute(0.001, turnLeftPage: false);

      expect(geometry.minX, closeTo(spineX, 0.01));
      expect(geometry.maxX, closeTo(spineX + pageWidth, 1.0));
    });
  });

  group('PageTurnGeometry — אמצע הדפדוף', () {
    test('הפרספקטיבה מגדילה רצועות מורמות, והשדרה נשארת מעוגנת', () {
      final geometry = compute(0.5);

      final spineStrip = geometry.strips.first;
      final edgeStrip = geometry.strips.last;
      expect(spineStrip.height, closeTo(height, height * 0.02));
      expect(edgeStrip.height, greaterThan(height));
      expect(edgeStrip.height, lessThan(height * 1.25));
    });

    test('ההתעקלות גורמת לקצה החופשי להוביל את הסיבוב', () {
      // מעט לפני האמצע: השדרה עוד לפני 90° אבל הקצה כבר עבר —
      // חלק מהרצועות מציגות חזית וחלק גב בו-זמנית.
      final geometry = compute(0.45);

      expect(geometry.strips.any((s) => s.showsFront), isTrue);
      expect(geometry.hasBackStrips, isTrue);
    });

    test('רצועות רציפות — אין חורים בציר האופקי', () {
      final geometry = compute(0.3);

      var covered = 0.0;
      for (final strip in geometry.strips) {
        covered += strip.width;
      }
      expect(covered, greaterThanOrEqualTo(geometry.maxX - geometry.minX));
    });
  });

  group('דפדוף אינטראקטיבי — מיפוי גרירה ל-progress', () {
    test('גרירה מלאה על פני הכפולה = דפדוף שלם, וההתקדמות ליניארית', () {
      expect(
        pageTurnDragProgress(dragDx: 800, directionSign: 1, pageWidth: 400),
        1.0,
      );
      expect(
        pageTurnDragProgress(dragDx: 400, directionSign: 1, pageWidth: 400),
        0.5,
      );
    });

    test('גרירה נגד כיוון הדפדוף נחסמת באפס ולא בערך שלילי', () {
      expect(
        pageTurnDragProgress(dragDx: -200, directionSign: 1, pageWidth: 400),
        0.0,
      );
      expect(
        pageTurnDragProgress(dragDx: 200, directionSign: -1, pageWidth: 400),
        0.0,
      );
    });
  });

  group('דפדוף אינטראקטיבי — החלטת שחרור', () {
    test('זריקה מהירה בכיוון הדפדוף משלימה גם בתחילת הדרך', () {
      expect(shouldCommitPageTurn(velocity: 900, progress: 0.1), isTrue);
    });

    test('זריקה מהירה נגד הכיוון מבטלת גם אחרי מחצית הדרך', () {
      expect(shouldCommitPageTurn(velocity: -900, progress: 0.8), isFalse);
    });

    test('שחרור איטי מוכרע לפי מעבר מחצית הדרך', () {
      expect(shouldCommitPageTurn(velocity: 0, progress: 0.51), isTrue);
      expect(shouldCommitPageTurn(velocity: 0, progress: 0.49), isFalse);
    });
  });

  group('PageTurnGeometry — חשיפת העמוד החדש', () {
    test('הקצה האחורי מתקדם מונוטונית לכיוון השדרה', () {
      var previous = double.negativeInfinity;
      for (var p = 0.05; p <= 1.0; p += 0.05) {
        final trailing = compute(p).trailingX(true);
        expect(trailing, greaterThanOrEqualTo(previous - 0.01));
        expect(trailing, lessThanOrEqualTo(spineX + 0.01));
        previous = trailing;
      }
    });

    test('הקצה הקדמי לא חורג מגבולות הכפולה', () {
      for (var p = 0.05; p <= 1.0; p += 0.05) {
        final leading = compute(p).leadingX(true);
        expect(leading, greaterThanOrEqualTo(spineX - 0.01));
        expect(leading, lessThanOrEqualTo(spineX + pageWidth * 1.2));
      }
    });
  });

  group('pageTurnDecorationFade — קישוט זמני בלבד', () {
    test('מתאפס בשני קצות האנימציה', () {
      // קישוט ששורד את הפריים האחרון "נופל" במעבר לתצוגה החיה.
      expect(pageTurnDecorationFade(0.0), 0.0);
      expect(pageTurnDecorationFade(1.0), closeTo(0.0, 1e-9));
    });

    test('מגיע לשיא באמצע הדפדוף', () {
      expect(pageTurnDecorationFade(0.5), closeTo(1.0, 1e-9));
    });

    test('חסום לטווח [0,1] גם עבור progress חורג', () {
      expect(pageTurnDecorationFade(-0.5), 0.0);
      expect(pageTurnDecorationFade(1.5), closeTo(0.0, 1e-9));
    });

    test('עוצמת ההצללה של הגאומטריה נגזרת מאותה דעיכה', () {
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final geometry = PageTurnGeometry.compute(
          spineX: 400,
          pageWidth: 400,
          height: 600,
          progress: p,
          turnLeftPage: true,
        );
        expect(geometry.shadeStrength, closeTo(pageTurnDecorationFade(p), 1e-9));
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';

void main() {
  group('BookProtection', () {
    test('ללא הגבלה — הכול מותר', () {
      const p = BookProtection.none;
      expect(p.isProtected, isFalse);
      expect(p.allowsEditableExport, isTrue);
      expect(p.allowsPdfExport, isTrue);
      expect(p.maxCopySegments, isNull);
      expect(p.maxPrintSegments, isNull);
      expect(p.allowsCopyOf(1000), isTrue);
    });

    test('רמה 1 — בלי ייצוא לעריכה, PDF והדפסה חופשיים, העתקה מוגבלת', () {
      const p = BookProtection(level: 1);
      const limit = BookProtection.copySegmentLimit;
      expect(p.allowsEditableExport, isFalse);
      expect(p.allowsPdfExport, isTrue);
      expect(p.maxPrintSegments, isNull);
      expect(p.maxCopySegments, limit);
      expect(p.allowsCopyOf(limit), isTrue);
      expect(p.allowsCopyOf(limit + 1), isFalse);
    });

    test('רמה 2 — גם בלי PDF, והדפסה מוגבלת', () {
      const p = BookProtection(level: 2);
      expect(p.allowsEditableExport, isFalse);
      expect(p.allowsPdfExport, isFalse);
      expect(p.maxPrintSegments, BookProtection.printSegmentLimit);
      expect(p.maxCopySegments, BookProtection.copySegmentLimit);
    });

    test('רמה לא מוכרת מעל 2 נחשבת למחמירה ביותר', () {
      const p = BookProtection(level: 7);
      expect(p.effectiveLevel, BookProtection.maxKnownLevel);
      expect(p.allowsPdfExport, isFalse);
      expect(p.maxPrintSegments, BookProtection.printSegmentLimit);
    });

    test('limitPrintEnd חותך רק ברמה 2', () {
      const limit = BookProtection.printSegmentLimit;
      const p2 = BookProtection(level: 2);
      expect(const BookProtection(level: 1).limitPrintEnd(10, 100), 100);
      expect(p2.limitPrintEnd(10, 100), 10 + limit);
      expect(p2.limitPrintEnd(10, 10 + limit), 10 + limit);
      expect(p2.limitPrintEnd(10, 10 + limit + 1), 10 + limit);
      expect(p2.limitPrintEnd(10, 20), 20);
    });

    test('strictest בוחר את הרמה הגבוהה ושומר את הבאנר של this', () {
      const a = BookProtection(level: 1, bannerText: 'באנר');
      const b = BookProtection(level: 2);
      expect(a.strictest(b).effectiveLevel, 2);
      expect(a.strictest(b).bannerText, 'באנר');
      expect(b.strictest(a), b);
    });
  });
}

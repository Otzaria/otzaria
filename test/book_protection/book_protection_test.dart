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

    test('רמה 1 — בלי ייצוא לעריכה, PDF והדפסה חופשיים, העתקה עד 5', () {
      const p = BookProtection(level: 1);
      expect(p.allowsEditableExport, isFalse);
      expect(p.allowsPdfExport, isTrue);
      expect(p.maxPrintSegments, isNull);
      expect(p.maxCopySegments, 5);
      expect(p.allowsCopyOf(5), isTrue);
      expect(p.allowsCopyOf(6), isFalse);
    });

    test('רמה 2 — גם בלי PDF, והדפסה עד 15', () {
      const p = BookProtection(level: 2);
      expect(p.allowsEditableExport, isFalse);
      expect(p.allowsPdfExport, isFalse);
      expect(p.maxPrintSegments, 15);
      expect(p.maxCopySegments, 5);
    });

    test('רמה לא מוכרת מעל 2 נחשבת למחמירה ביותר', () {
      const p = BookProtection(level: 7);
      expect(p.effectiveLevel, BookProtection.maxKnownLevel);
      expect(p.allowsPdfExport, isFalse);
      expect(p.maxPrintSegments, 15);
    });

    test('limitPrintEnd חותך רק ברמה 2', () {
      expect(const BookProtection(level: 1).limitPrintEnd(10, 100), 100);
      expect(const BookProtection(level: 2).limitPrintEnd(10, 100), 25);
      expect(const BookProtection(level: 2).limitPrintEnd(10, 20), 20);
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

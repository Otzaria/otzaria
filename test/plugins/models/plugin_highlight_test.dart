import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';

void main() {
  group('PluginHighlight — unit tests', () {
    test('יוצר הדגשת שורה שלמה ללא start/end', () {
      final h = PluginHighlight(
        bookId: 'book1',
        index: 5,
        pluginId: 'plugin1',
      );
      expect(h.isInline, isFalse);
      expect(h.start, isNull);
      expect(h.end, isNull);
    });

    test('יוצר הדגשה מדויקת עם start ו-end', () {
      final h = PluginHighlight(
        bookId: 'book1',
        index: 3,
        pluginId: 'plugin1',
        start: 10,
        end: 20,
      );
      expect(h.isInline, isTrue);
      expect(h.start, equals(10));
      expect(h.end, equals(20));
    });

    test('isInline מחזיר false כש-start בלבד קיים', () {
      final h = PluginHighlight(
        bookId: 'book1',
        index: 0,
        pluginId: 'plugin1',
        start: 5,
      );
      expect(h.isInline, isFalse);
    });

    test('isInline מחזיר false כש-end בלבד קיים', () {
      final h = PluginHighlight(
        bookId: 'book1',
        index: 0,
        pluginId: 'plugin1',
        end: 5,
      );
      expect(h.isInline, isFalse);
    });

    test('isInline מחזיר true כש-start == end (הדגשת תו יחיד)', () {
      final h = PluginHighlight(
        bookId: 'book1',
        index: 0,
        pluginId: 'plugin1',
        start: 7,
        end: 7,
      );
      expect(h.isInline, isTrue);
    });

    group('toJson', () {
      test('הדגשת שורה שלמה — toJson לא מכיל start/end', () {
        final h = PluginHighlight(
          bookId: 'b1',
          index: 2,
          pluginId: 'p1',
          color: '#FF0000',
          label: 'important',
        );
        final json = h.toJson();
        expect(json['bookId'], equals('b1'));
        expect(json['index'], equals(2));
        expect(json['pluginId'], equals('p1'));
        expect(json['color'], equals('#FF0000'));
        expect(json['label'], equals('important'));
        expect(json.containsKey('start'), isFalse);
        expect(json.containsKey('end'), isFalse);
      });

      test('הדגשה מדויקת — toJson מכיל start ו-end', () {
        final h = PluginHighlight(
          bookId: 'b2',
          index: 10,
          pluginId: 'p2',
          start: 3,
          end: 15,
        );
        final json = h.toJson();
        expect(json['start'], equals(3));
        expect(json['end'], equals(15));
      });

      test('ללא color ו-label — לא מופיעים ב-toJson', () {
        final h = PluginHighlight(
          bookId: 'b3',
          index: 1,
          pluginId: 'p3',
        );
        final json = h.toJson();
        expect(json.containsKey('color'), isFalse);
        expect(json.containsKey('label'), isFalse);
      });

      test('עם color ו-label — מופיעים ב-toJson', () {
        final h = PluginHighlight(
          bookId: 'b4',
          index: 1,
          pluginId: 'p4',
          color: '#00FF00',
          label: 'test',
        );
        final json = h.toJson();
        expect(json['color'], equals('#00FF00'));
        expect(json['label'], equals('test'));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Property-Based Tests
  // ---------------------------------------------------------------------------

  group(
    'Feature: plugin-api-enhancements, Property 1: highlight round-trip',
    () {
      // **Validates: Requirements 1.4, 2.2**
      //
      // לכל הדגשה מדויקת תקינה (0 ≤ start ≤ end),
      // toJson() חייב לכלול את bookId, index, start, end בדיוק כפי שהוגדרו.
      test('round-trip: נתוני הדגשה מדויקת נשמרים ומוחזרים בשלמותם', () {
        final rng = Random(42);

        for (var i = 0; i < 200; i++) {
          final bookId = 'book_${rng.nextInt(1000)}';
          final index = rng.nextInt(10000);
          final start = rng.nextInt(500);
          final end = start + rng.nextInt(500); // end >= start תמיד
          final pluginId = 'plugin_${rng.nextInt(50)}';
          final color = rng.nextBool()
              ? '#${rng.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
              : null;
          final label = rng.nextBool() ? 'label_${rng.nextInt(100)}' : null;

          final highlight = PluginHighlight(
            bookId: bookId,
            index: index,
            pluginId: pluginId,
            color: color,
            label: label,
            start: start,
            end: end,
          );

          final json = highlight.toJson();

          // round-trip: כל השדות חייבים להיות זהים
          expect(json['bookId'], equals(bookId),
              reason: 'iteration $i: bookId mismatch');
          expect(json['index'], equals(index),
              reason: 'iteration $i: index mismatch');
          expect(json['pluginId'], equals(pluginId),
              reason: 'iteration $i: pluginId mismatch');
          expect(json['start'], equals(start),
              reason: 'iteration $i: start mismatch');
          expect(json['end'], equals(end),
              reason: 'iteration $i: end mismatch');

          // שדות אופציונליים
          if (color != null) {
            expect(json['color'], equals(color),
                reason: 'iteration $i: color mismatch');
          } else {
            expect(json.containsKey('color'), isFalse,
                reason: 'iteration $i: color should be absent');
          }
          if (label != null) {
            expect(json['label'], equals(label),
                reason: 'iteration $i: label mismatch');
          } else {
            expect(json.containsKey('label'), isFalse,
                reason: 'iteration $i: label should be absent');
          }

          // isInline חייב להיות true
          expect(highlight.isInline, isTrue,
              reason: 'iteration $i: isInline should be true');
        }
      });
    },
  );

  group(
    'Feature: plugin-api-enhancements, Property 3: backward-compat no-start-end',
    () {
      // **Validates: Requirements 1.7, 6.1, 6.2**
      //
      // לכל הדגשה שנוצרה ללא start ו-end,
      // toJson() לא יכלול את המפתחות 'start' ו-'end' כלל (לא null, אלא העדרם).
      test(
        'תאימות לאחור: הדגשות ללא start/end לא מחזירות שדות אלה ב-toJson',
        () {
          final rng = Random(99);

          for (var i = 0; i < 200; i++) {
            final bookId = 'book_${rng.nextInt(1000)}';
            final index = rng.nextInt(10000);
            final pluginId = 'plugin_${rng.nextInt(50)}';
            final color = rng.nextBool() ? '#FFFF00' : null;
            final label = rng.nextBool() ? 'lbl_${rng.nextInt(100)}' : null;

            final highlight = PluginHighlight(
              bookId: bookId,
              index: index,
              pluginId: pluginId,
              color: color,
              label: label,
              // ללא start ו-end
            );

            final json = highlight.toJson();

            // המפתחות 'start' ו-'end' חייבים להיות נעדרים לחלוטין
            expect(json.containsKey('start'), isFalse,
                reason: 'iteration $i: "start" key must be absent, not null');
            expect(json.containsKey('end'), isFalse,
                reason: 'iteration $i: "end" key must be absent, not null');

            // השדות הבסיסיים חייבים להיות נוכחים
            expect(json['bookId'], equals(bookId),
                reason: 'iteration $i: bookId mismatch');
            expect(json['index'], equals(index),
                reason: 'iteration $i: index mismatch');
            expect(json['pluginId'], equals(pluginId),
                reason: 'iteration $i: pluginId mismatch');

            // isInline חייב להיות false
            expect(highlight.isInline, isFalse,
                reason: 'iteration $i: isInline should be false');
          }
        },
      );
    },
  );
}

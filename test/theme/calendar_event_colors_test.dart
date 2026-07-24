import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/calendar_event_colors.dart';

void main() {
  group('CalendarEventColors.colorForIndex', () {
    test('null מחזיר null (ללא צבע מיוחד)', () {
      expect(CalendarEventColors.colorForIndex(null, Brightness.light), isNull);
    });

    test('אינדקס שלילי מחזיר null', () {
      expect(CalendarEventColors.colorForIndex(-1, Brightness.light), isNull);
    });

    test('אינדקס מחוץ לטווח הפלטה מחזיר null', () {
      expect(
        CalendarEventColors.colorForIndex(
          CalendarEventColors.count,
          Brightness.light,
        ),
        isNull,
      );
    });

    test('אינדקס תקין מחזיר את צבע הפלטה במצב בהיר', () {
      final color = CalendarEventColors.colorForIndex(0, Brightness.light);
      expect(color, CalendarEventColors.palette[0].color);
    });

    test('במצב כהה מוחזר גוון בהיר יותר, שונה מהמצב הבהיר', () {
      for (int i = 0; i < CalendarEventColors.count; i++) {
        final light = CalendarEventColors.colorForIndex(i, Brightness.light)!;
        final dark = CalendarEventColors.colorForIndex(i, Brightness.dark)!;
        expect(dark, isNot(light), reason: 'אינדקס $i');
        expect(
          HSLColor.fromColor(dark).lightness,
          greaterThan(HSLColor.fromColor(light).lightness),
          reason: 'אינדקס $i',
        );
      }
    });
  });

  group('CalendarEventColors.nameOf', () {
    test('אינדקס תקין מחזיר שם עברי, לא-תקין מחזיר null', () {
      expect(CalendarEventColors.nameOf(0), 'אדום');
      expect(CalendarEventColors.nameOf(null), isNull);
      expect(CalendarEventColors.nameOf(-1), isNull);
      expect(CalendarEventColors.nameOf(CalendarEventColors.count), isNull);
    });
  });
}

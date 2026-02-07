import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/calendar_cubit.dart';
import 'package:kosher_dart/kosher_dart.dart';

void main() {
  group('CalendarCubit Jewish month navigation', () {
    test('next month handles Adar I -> Adar II and no year rollover to Nissan',
        () {
      // Create a JewishDate for a known leap year at Adar I (month 12)
      final jewish = JewishDate();
      // 5784 is a leap year in the 19-year cycle
      jewish.setJewishDate(5784, 12, 15); // Middle of Adar I

      expect(jewish.isJewishLeapYear(), isTrue);
      expect(jewish.getJewishMonth(), 12);

      final next = computeNextJewishMonth(jewish);
      expect(next.getJewishYear(), 5784);
      expect(next.getJewishMonth(), 13,
          reason: 'Should move to Adar II same year');

      final afterAdarII = computeNextJewishMonth(next);
      expect(afterAdarII.getJewishYear(), 5784,
          reason: 'After Adar II go to Nissan in same Jewish year');
      expect(afterAdarII.getJewishMonth(), 1);
    });

    test('previous month handles Nissan -> last Adar in same year', () {
      // Nissan of a leap year
      final nissan = JewishDate();
      nissan.setJewishDate(5784, 1, 7);
      expect(nissan.isJewishLeapYear(), isTrue);
      expect(nissan.getJewishMonth(), 1);

      final prev = computePreviousJewishMonth(nissan);
      expect(prev.getJewishYear(), 5784,
          reason: 'Nissan -> Adar stays in same Jewish year');
      expect(prev.getJewishMonth(), 13,
          reason: '5784 is leap; previous month is Adar II');
    });

    test('previous month handles Adar II -> Adar I within leap year', () {
      final adarII = JewishDate();
      adarII.setJewishDate(5784, 13, 3);
      expect(adarII.isJewishLeapYear(), isTrue);
      final prev = computePreviousJewishMonth(adarII);
      expect(prev.getJewishMonth(), 12);
      expect(prev.getJewishYear(), 5784);
    });
  });
}

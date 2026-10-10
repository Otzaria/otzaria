import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';

/// המימוש המקורי, שבנה את כל גבולות התקופות מחדש לכל סימניה.
String _referenceKey(DateTime? date, DateTime now) {
  if (date == null) return '8_older';
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final startOfThisWeek = today.subtract(Duration(days: today.weekday % 7));
  final startOfLastWeek = startOfThisWeek.subtract(const Duration(days: 7));
  final startOfThisMonth = DateTime(now.year, now.month, 1);
  final startOfPrevMonth = now.month == 1
      ? DateTime(now.year - 1, 12, 1)
      : DateTime(now.year, now.month - 1, 1);
  final startOfThisYear = DateTime(now.year, 1, 1);
  final d = DateTime(date.year, date.month, date.day);
  if (!d.isBefore(today)) return '1_today';
  if (!d.isBefore(yesterday)) return '2_yesterday';
  if (!d.isBefore(startOfThisWeek)) return '3_this_week';
  if (!d.isBefore(startOfLastWeek)) return '4_last_week';
  if (!d.isBefore(startOfThisMonth)) return '5_this_month';
  if (!d.isBefore(startOfPrevMonth)) return '6_prev_month';
  if (!d.isBefore(startOfThisYear)) return '7_this_year';
  return '8_older';
}

void main() {
  group('BookmarkDateGroups', () {
    test('גבולות התקופות נבנים פעם אחת ביום ולא לכל סימניה', () {
      final groups = BookmarkDateGroups();
      final morning = DateTime(2026, 10, 6, 8);
      final starts = groups.periodStarts(morning);
      expect(
        identical(
          groups.periodStarts(morning.add(const Duration(hours: 12))),
          starts,
        ),
        isTrue,
      );
      expect(
        identical(groups.periodStarts(DateTime(2026, 10, 7, 0, 1)), starts),
        isFalse,
      );
    });

    test('מפתח הקבוצה זהה למימוש המקורי, כולל מעבר יום ושנה', () {
      final groups = BookmarkDateGroups();
      final nows = [
        DateTime(2026, 10, 6, 23, 59),
        DateTime(2026, 10, 7, 0, 1),
        DateTime(2026, 1, 1, 9),
        DateTime(2026, 3, 1, 12),
        DateTime(2026, 10, 4, 10),
      ];
      for (final now in nows) {
        expect(groups.keyFor(null, now: now), '8_older');
        for (var h = 0; h < 24 * 500; h += 7) {
          final date = now.subtract(Duration(hours: h));
          expect(
            groups.keyFor(date, now: now),
            _referenceKey(date, now),
            reason: 'now=$now date=$date',
          );
        }
      }
    });

    test('תווית לפי המפתח', () {
      final groups = BookmarkDateGroups();
      final now = DateTime(2026, 10, 6, 12);
      expect(groups.labelFor(now, now: now), 'היום');
      expect(groups.labelFor(null, now: now), 'ישן יותר');
    });
  });
}

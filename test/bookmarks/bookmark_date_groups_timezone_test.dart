import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';

// TZ changes only the tester process; restore it before the next test.
void _setTimezone(String? zone) {
  final libc = DynamicLibrary.process();
  final setenv = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)
      >('setenv');
  final unsetenv = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('unsetenv');
  final tzset = libc.lookupFunction<Void Function(), void Function()>('tzset');
  final name = 'TZ'.toNativeUtf8();
  final value = zone?.toNativeUtf8();
  try {
    expect(value == null ? unsetenv(name) : setenv(name, value, 1), 0);
    tzset();
  } finally {
    calloc.free(name);
    if (value != null) calloc.free(value);
  }
}

void main() {
  final supportsTimezone = Platform.isLinux || Platform.isMacOS;

  test('מעבר אזור זמן באותו יום מעדכן את קבוצת היום והתווית', () {
    final originalZone = Platform.environment['TZ'];
    try {
      _setTimezone('UTC');
      final groups = BookmarkDateGroups();
      final initial = DateTime(2026, 10, 7, 12);
      final instant = initial.millisecondsSinceEpoch;
      final cached = groups.periodStarts(initial);
      expect(initial.timeZoneOffset, Duration.zero);

      _setTimezone('Asia/Jerusalem');
      final now = DateTime.fromMillisecondsSinceEpoch(instant);
      expect(now.timeZoneOffset, const Duration(hours: 3));
      expect(now.day, 7);
      final bookmarkDate = DateTime(2026, 10, 7, 13);
      expect(groups.keyFor(bookmarkDate, now: now), '1_today');
      expect(groups.labelFor(bookmarkDate, now: now), 'היום');
      expect(identical(groups.periodStarts(now), cached), isFalse);
    } finally {
      _setTimezone(originalZone);
    }
  }, skip: !supportsTimezone);

  test('היסט נוכחי זהה אינו מסתיר שינוי בגבול חודש קודם', () {
    final originalZone = Platform.environment['TZ'];
    try {
      _setTimezone('Africa/Algiers');
      final groups = BookmarkDateGroups();
      final initial = DateTime(2026, 11, 7, 12);
      final instant = initial.millisecondsSinceEpoch;
      final cached = groups.periodStarts(initial);
      final initialOffset = initial.timeZoneOffset;
      final initialName = initial.timeZoneName;
      expect(cached[5].timeZoneOffset, const Duration(hours: 1));

      _setTimezone('Europe/Paris');
      final now = DateTime.fromMillisecondsSinceEpoch(instant);
      expect(now.timeZoneOffset, initialOffset);
      expect(now.timeZoneName, initialName);
      expect(DateTime(2026, 10, 1).timeZoneOffset, const Duration(hours: 2));
      final bookmarkDate = DateTime(2026, 10, 1, 12);
      expect(groups.keyFor(bookmarkDate, now: now), '6_prev_month');
      expect(groups.labelFor(bookmarkDate, now: now), 'חודש קודם');
      expect(identical(groups.periodStarts(now), cached), isFalse);
    } finally {
      _setTimezone(originalZone);
    }
  }, skip: !supportsTimezone);
}

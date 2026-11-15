import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/reading_history_stacks.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/reading_tab_history.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

import '../../helpers/memory_settings_cache.dart';

Map<String, dynamic> _throughJson(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

PdfReadingLocation _page(int page) => PdfReadingLocation(
  pageNumber: page,
  pageOffset: Offset(10, page * 3.5),
  zoom: 1.5,
);

/// טאב טקסט שחזר אחורה פעם אחת: אחורה — 12, קדימה — 80, עכשיו — 40.
Future<TextBookTab> _textTabWithHistory() async {
  final tab = TextBookTab(
    book: TextBook(title: 'ספר בדיקה'),
    index: 12,
    initialReadingAnchor: const ReadingAnchor(line: 12),
  );
  await tab.lines.jumpToLine(40);
  await tab.lines.jumpToLine(80);
  await tab.lines.goBack();
  return tab;
}

int? _decodeInt(Object? value) => value is int ? value : null;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  group('מחסניות ההיסטוריה', () {
    test('נשמרים רק 20 היעדים האחרונים בכל כיוון', () {
      final json = encodeReadingHistory<int>(
        back: List.generate(30, (i) => i),
        forward: [100],
        at: () => 50,
        encode: (value) => value,
      )!;
      expect(json['back'], List.generate(20, (i) => i + 10));
      expect(json['forward'], [100]);
      expect(json['at'], 50);
    });

    test('בלי היסטוריה אין מה לשמור', () {
      expect(
        encodeReadingHistory<int>(
          back: const [],
          forward: const [],
          at: () => 5,
          encode: (value) => value,
        ),
        isNull,
      );
    });

    test('פתיחה ביעד אחר: המיקום השמור לחזרה, ואין קדימה', () {
      final json = {
        'back': [1, 2],
        'forward': [9],
        'at': 5,
      };
      final kept = decodeReadingHistory(json, _decodeInt)!;
      expect(kept.back, [1, 2]);
      expect(kept.forward, [9]);
      final jumped = decodeReadingHistory(json, _decodeInt, asNewJump: true)!;
      expect(jumped.back, [1, 2, 5]);
      expect(jumped.forward, isEmpty);
    });

    test('ערכים פגומים מדולגים ומבנה פגום מתעלם', () {
      final stacks = decodeReadingHistory({
        'back': [1, 'x', null, 3],
        'forward': 'invalid',
      }, _decodeInt)!;
      expect(stacks.back, [1, 3]);
      expect(stacks.forward, isEmpty);
      expect(decodeReadingHistory('invalid', _decodeInt), isNull);
      expect(decodeReadingHistory(null, _decodeInt), isNull);
    });
  });

  group('טאב טקסט', () {
    test('ההיסטוריה שורדת שמירה ושחזור של הטאב ושכפול', () async {
      final tab = await _textTabWithHistory();
      addTearDown(tab.dispose);
      final restored = TextBookTab.fromJson(_throughJson(tab.toJson()));
      addTearDown(restored.dispose);
      final clone = tab.clone() as TextBookTab;
      addTearDown(clone.dispose);
      for (final copy in [restored, clone]) {
        expect(copy.lines.history.value.back!.line, 12);
        expect(copy.lines.history.value.forward!.line, 80);
        await copy.lines.goForward();
        expect(copy.lines.captureAnchor()!.line, 80);
        expect(copy.lines.history.value.back!.line, 40);
      }
    });

    test('JSON בלי היסטוריה נטען בלי יעדים', () {
      final restored = TextBookTab.fromJson({
        'title': 'ספר בדיקה',
        'initalIndex': 12,
        'commentators': <String>[],
        'showLeftPane': false,
      });
      addTearDown(restored.dispose);
      expect(restored.lines.history.value, (back: null, forward: null));
      expect(restored.toJson().containsKey('navigationHistory'), isFalse);
    });

    test(
      'ספר שנסגר ונפתח במקומו מהיסטוריית הקריאה חוזר עם ההיסטוריה',
      () async {
        final tab = await _textTabWithHistory();
        addTearDown(tab.dispose);
        final entry = Bookmark(
          ref: 'ספר בדיקה',
          book: tab.book,
          index: 40,
          readingAnchor: tab.lines.captureAnchor(),
          navigationHistory: readingTabNavigationHistory(tab),
        );
        final saved = Bookmark.fromJson(_throughJson(entry.toJson()));
        final reopened = tabFromBookmark(saved) as TextBookTab;
        addTearDown(reopened.dispose);
        expect(reopened.readingAnchor.line, 40);
        expect(reopened.lines.history.value.back!.line, 12);
        expect(reopened.lines.history.value.forward!.line, 80);
      },
    );

    test('סימנייה ישנה וסימנייה רגילה אינן נושאות היסטוריה', () {
      final saved = Bookmark.fromJson(
        _throughJson(
          Bookmark(
            ref: 'ספר בדיקה',
            book: TextBook(title: 'ספר בדיקה'),
            index: 3,
          ).toJson(),
        ),
      );
      expect(saved.navigationHistory, isNull);
      expect(saved.toJson().containsKey('navigationHistory'), isFalse);
      final tab = tabFromBookmark(saved) as TextBookTab;
      addTearDown(tab.dispose);
      expect(tab.lines.history.value, (back: null, forward: null));
    });
  });

  group('טאב PDF', () {
    test('המיקום נשמר עם העמוד, ההיסט והזום', () {
      final location = _page(4);
      expect(
        PdfReadingLocation.tryFromJson(
          jsonDecode(jsonEncode(location.toJson())),
        ),
        location,
      );
      expect(PdfReadingLocation.tryFromJson({'page': 0}), isNull);
      expect(
        PdfReadingLocation.tryFromJson({
          'page': 2,
          'dx': 0,
          'dy': 0,
          'zoom': 0,
        }),
        isNull,
      );
    });

    test('ההיסטוריה שורדת שמירה ושחזור של הטאב ושכפול', () {
      final tab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 7,
      );
      addTearDown(tab.dispose);
      tab.navigationHistory
        ..remember(_page(2))
        ..remember(_page(5));
      tab.navigationHistory.takePrevious(_page(9));

      final restored = PdfBookTab.fromJson(_throughJson(tab.toJson()));
      addTearDown(restored.dispose);
      final clone = tab.clone() as PdfBookTab;
      addTearDown(clone.dispose);
      for (final copy in [restored, clone]) {
        expect(copy.navigationHistory.last, _page(2));
        expect(copy.navigationHistory.next, _page(9));
      }
    });

    test('JSON בלי היסטוריה נטען בלי יעדים', () {
      final restored = PdfBookTab.fromJson({
        'path': 'a.pdf',
        'pageNumber': 3,
        'showLeftPane': false,
      });
      addTearDown(restored.dispose);
      expect(restored.navigationHistory.canGoBack, isFalse);
      expect(restored.navigationHistory.canGoForward, isFalse);
    });

    test('פתיחה ביעד אחר מוסיפה את המיקום השמור לחזרה', () {
      final tab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 1,
      );
      addTearDown(tab.dispose);
      restoreReadingTabNavigationHistory(tab, {
        'back': [_page(2).toJson()],
        'forward': [_page(8).toJson()],
        'at': _page(6).toJson(),
      }, asNewJump: true);
      expect(tab.navigationHistory.last, _page(6));
      expect(tab.navigationHistory.canGoForward, isFalse);
      tab.navigationHistory.takePrevious();
      expect(tab.navigationHistory.last, _page(2));
    });
  });
}

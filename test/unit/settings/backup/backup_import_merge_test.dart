import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/settings/services/backup/backup_import_merge.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/workspaces/workspace.dart';

void main() {
  Bookmark bookmark({
    String ref = 'בראשית א',
    int index = 0,
    String title = 'ספר א',
    String? label,
    bool isSearch = false,
  }) => Bookmark.fromJson({
    'ref': ref,
    'index': index,
    'isSearch': isSearch,
    'label': label,
    'book': {'title': title, 'type': 'TextBook'},
  });

  group('סימניות', () {
    test('סימניה זהה אינה מוכפלת, וחדשה מתווספת בסוף', () {
      final local = [
        bookmark(ref: 'בראשית א'),
        bookmark(ref: 'בראשית ב', index: 1),
      ];
      final incoming = [
        bookmark(ref: 'בראשית ב', index: 1),
        bookmark(ref: 'שמות א', title: 'ספר ב'),
      ];

      final result = BackupImportMerge.mergeBookmarks(local, incoming);

      expect(result.added, 1);
      expect(result.merged.length, 3);
      expect(result.merged.last.ref, 'שמות א');
    });

    test('תיאור שנערך מקומית אינו יוצר כפילות ואינו נדרס', () {
      final local = [bookmark(label: 'התיאור שלי')];
      final incoming = [bookmark(label: 'תיאור אחר')];

      final result = BackupImportMerge.mergeBookmarks(local, incoming);

      expect(result.added, 0);
      expect(result.merged.single.label, 'התיאור שלי');
    });

    test('אותו מיקום בספרים שונים אינו נחשב כפול', () {
      final result = BackupImportMerge.mergeBookmarks(
        [bookmark(title: 'ספר א')],
        [bookmark(title: 'ספר ב')],
      );

      expect(result.added, 1);
    });

    test(
      'סימניה שנבדלת רק ב-ref אינה מתווספת (issue: סריקת באגים 8,9,10)',
      () {
        final result = BackupImportMerge.mergeBookmarks(
          [bookmark(ref: 'בראשית א')],
          [bookmark(ref: 'בראשית א, א')],
        );

        expect(result.added, 0);
        expect(result.merged.single.ref, 'בראשית א');
      },
    );
  });

  group('היסטוריה', () {
    test('המיובאות מפנות את הרשומות המקומיות הישנות בתקרה', () {
      final local = List.generate(
        BackupImportMerge.maxHistory,
        (i) => bookmark(ref: 'מקומי $i', title: 'מקומי $i'),
      );
      final incoming = [bookmark(ref: 'מיובא', title: 'מיובא')];

      final result = BackupImportMerge.mergeHistory(local, incoming);

      expect(result.added, 1);
      expect(result.merged.length, BackupImportMerge.maxHistory);
      expect(result.merged.first.ref, 'מקומי 0');
      expect(result.merged.last.ref, 'מיובא');
      expect(result.merged.any((item) => item.ref == 'מקומי 199'), isFalse);
    });

    test('סימניית חיפוש מזוהה לפי טקסט החיפוש', () {
      final result = BackupImportMerge.mergeHistory(
        [bookmark(ref: 'רש"י', isSearch: true)],
        [
          bookmark(ref: 'רש"י', isSearch: true),
          bookmark(ref: 'רמב"ן', isSearch: true),
        ],
      );

      expect(result.added, 1);
    });

    test(
      'רשומה אחת לכל ספר — המקומית מנצחת (issue: סריקת באגים 8,9,10)',
      () {
        final result = BackupImportMerge.mergeHistory(
          [bookmark(ref: 'בראשית א', index: 0)],
          [bookmark(ref: 'בראשית ה', index: 40)],
        );

        expect(result.added, 0);
        expect(result.merged.single.ref, 'בראשית א');
      },
    );

    test('מתחת לתקרה — המיובאות נוספות', () {
      final result = BackupImportMerge.mergeHistory(
        [bookmark(ref: 'מקומי', title: 'מקומי')],
        [bookmark(ref: 'מיובא', title: 'מיובא')],
      );

      expect(result.added, 1);
      expect(result.merged.length, 2);
    });
  });

  group('שמור וזכור', () {
    String progress(Map<String, Object> books) => json.encode(books);

    test('ספר חדש נוסף, וההתקדמות המקומית מנצחת', () {
      final result = BackupImportMerge.mergeShamorZachor(
        {
          'sz:progress_by_id': progress({
            '1': {'pages': 5},
          }),
        },
        {
          'sz:progress_by_id': progress({
            '1': {'pages': 2},
            '2': {'pages': 7},
          }),
        },
      );

      expect(result.addedBooks, 1);
      final merged =
          json.decode(result.toWrite['sz:progress_by_id'] as String) as Map;
      expect((merged['1'] as Map)['pages'], 5);
      expect((merged['2'] as Map)['pages'], 7);
    });

    test('אין ספר חדש — אין כתיבה כלל', () {
      final local = {
        'sz:progress_by_id': progress({
          '1': {'pages': 5},
        }),
      };
      final result = BackupImportMerge.mergeShamorZachor(local, {
        'sz:progress_by_id': progress({
          '1': {'pages': 2},
        }),
      });

      expect(result.addedBooks, 0);
      expect(result.toWrite, isEmpty);
    });

    test('ספרים במעקב מאוחדים', () {
      final result = BackupImportMerge.mergeShamorZachor(
        {
          'sz:tracked_books': json.encode([1, 2]),
        },
        {
          'sz:tracked_books': json.encode([2, 3]),
        },
      );

      expect(
        json.decode(result.toWrite['sz:tracked_books'] as String),
        [1, 2, 3],
      );
    });

    test('מפתח אחר נכתב רק אם אינו קיים מקומית', () {
      final result = BackupImportMerge.mergeShamorZachor(
        {'sz:sidebar_visible': false},
        {'sz:sidebar_visible': true, 'sz:other': 'x'},
      );

      expect(result.toWrite.containsKey('sz:sidebar_visible'), isFalse);
      expect(result.toWrite['sz:other'], 'x');
    });
  });

  group('שולחנות עבודה', () {
    Workspace workspace(String id, String name) =>
        Workspace(id: id, name: name, tabs: const []);

    test('שולחן שכבר יובא (אותו מזהה) מדולג — ייבוא חוזר אינו מכפיל', () {
      final toAdd = BackupImportMerge.workspacesToAdd(
        [workspace('a', 'לימוד')],
        [workspace('a', 'לימוד'), workspace('b', 'חברותא')],
      );

      expect(toAdd.length, 1);
      expect(toAdd.single.id, 'b');
    });

    test('שם תפוס מקבל סיומת, והמזהה נשמר', () {
      final toAdd = BackupImportMerge.workspacesToAdd(
        [workspace('a', 'לימוד')],
        [workspace('b', 'לימוד')],
      );

      expect(toAdd.single.id, 'b');
      expect(toAdd.single.name, 'לימוד (ממכשיר אחר)');
    });

    test('שני שולחנות מיובאים באותו שם מקבלים שמות נבדלים', () {
      final toAdd = BackupImportMerge.workspacesToAdd(
        [workspace('a', 'לימוד')],
        [workspace('b', 'לימוד'), workspace('c', 'לימוד')],
      );

      expect(toAdd.map((w) => w.name), [
        'לימוד (ממכשיר אחר)',
        'לימוד (ממכשיר אחר 2)',
      ]);
    });

    test('שולחן מקובע נשאר מקובע, וצד החלונית הפעילה נשמר', () {
      final pinned = Workspace(
        id: 'b',
        name: 'לימוד',
        tabs: const [],
        activePane: kLeftPaneSide,
        isPinned: true,
      );

      final toAdd = BackupImportMerge.workspacesToAdd(
        [workspace('a', 'לימוד')],
        [pinned],
      );

      expect(toAdd.single.isPinned, isTrue);
      expect(toAdd.single.activePane, kLeftPaneSide);
      expect(toAdd.single.name, 'לימוד (ממכשיר אחר)');
    });
  });
}

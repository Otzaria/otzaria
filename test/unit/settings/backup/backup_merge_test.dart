import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/backup/backup_merge.dart';

void main() {
  final olderTs = DateTime(2025, 1, 1);
  final newerTs = DateTime(2025, 6, 1);
  final now = DateTime(2025, 7, 1);

  Map<String, dynamic> merge(
    Map<String, dynamic> older,
    Map<String, dynamic> newer,
  ) => BackupMerge.merge(
    older,
    newer,
    olderTimestamp: olderTs,
    newerTimestamp: newerTs,
    now: now,
  );

  Map<String, dynamic> bookmark(String ref, {String title = 'ספר'}) => {
    'ref': ref,
    'index': 1,
    'targetKind': 'book',
    'isSearch': false,
    'book': {'title': title},
  };

  group('parseManifestTimestamp', () {
    test('ממיר פורמט קובץ (מקפים במקום נקודתיים)', () {
      final parsed = BackupMerge.parseManifestTimestamp(
        '2026-07-05T12-34-56.789',
      );
      expect(parsed, DateTime(2026, 7, 5, 12, 34, 56, 789));
    });

    test('מחזיר null על קלט לא תקין', () {
      expect(BackupMerge.parseManifestTimestamp('garbage'), isNull);
      expect(BackupMerge.parseManifestTimestamp(null), isNull);
    });
  });

  group('סימניות', () {
    test('פריט ישן-בלבד נשמר עם lastSeenAt; פריט חדש מנצח', () {
      final merged = merge(
        {
          'bookmarks': [bookmark('דף ב'), bookmark('דף ג')],
        },
        {
          'bookmarks': [
            {...bookmark('דף ב'), 'label': 'עודכן'},
          ],
        },
      );

      final bookmarks = (merged['bookmarks'] as List).cast<Map>();
      expect(bookmarks, hasLength(2));

      final updated = bookmarks.firstWhere((b) => b['ref'] == 'דף ב');
      expect(updated['label'], 'עודכן');
      expect(updated['lastSeenAt'], newerTs.toIso8601String());

      final oldOnly = bookmarks.firstWhere((b) => b['ref'] == 'דף ג');
      expect(oldOnly['lastSeenAt'], olderTs.toIso8601String());
    });

    test('פריט שחצה את גיל הארכיון נגזם', () {
      final ancient = DateTime(2020, 1, 1).toIso8601String();
      final merged = merge(
        {
          'bookmarks': [
            {...bookmark('עתיק'), 'lastSeenAt': ancient},
            bookmark('רגיל'),
          ],
        },
        {'bookmarks': const []},
      );

      final refs = (merged['bookmarks'] as List)
          .map((b) => (b as Map)['ref'])
          .toList();
      expect(refs, ['רגיל']);
    });
  });

  group('הגדרות', () {
    test('החדש מנצח תמיד — ללא איחוד ערכים ישנים', () {
      final merged = merge(
        {
          'settings': {'key-a': 'old', 'key-old-only': 'x'},
        },
        {
          'settings': {'key-a': 'new'},
        },
      );
      expect(merged['settings'], {'key-a': 'new'});
    });

    test('אם חסר בחדש — נלקח מהישן', () {
      final merged = merge(
        {
          'settings': {'key-a': 'old'},
        },
        const {},
      );
      expect(merged['settings'], {'key-a': 'old'});
    });
  });

  group('הערות אישיות', () {
    Map<String, dynamic> note(
      String id,
      String updatedAt, {
      String content = 'תוכן',
      String bookId = 'ספר',
    }) => {
      'id': id,
      'bookId': bookId,
      'content': content,
      'updatedAt': updatedAt,
    };

    test('איחוד לפי id — updatedAt המאוחר מנצח גם אם הוא בישן', () {
      final merged = merge(
        {
          'notes': [
            {
              'bookId': 'ספר',
              'notes': [
                note('1', '2025-05-01T00:00:00', content: 'גרסה מאוחרת'),
                note('2', '2025-01-01T00:00:00'),
              ],
            },
          ],
        },
        {
          'notes': [
            {
              'bookId': 'ספר',
              'notes': [
                note('1', '2025-02-01T00:00:00', content: 'גרסה מוקדמת'),
              ],
            },
          ],
        },
      );

      final books = (merged['notes'] as List).cast<Map>();
      expect(books, hasLength(1));
      final notes = (books.single['notes'] as List).cast<Map>();
      expect(notes, hasLength(2));
      final note1 = notes.firstWhere((n) => n['id'] == '1');
      expect(note1['content'], 'גרסה מאוחרת');
    });
  });

  group('שמור וזכור', () {
    test('מיזוג פר-ספר: החדש דורס ספר קיים, ספר ישן-בלבד נשמר', () {
      final merged = merge(
        {
          'shamorZachor': {
            'sz:progress_by_id': json.encode({
              'ברכות': {
                '2': {'learn': true, 'review1': true},
              },
              'שבת': {
                '2': {'learn': true},
              },
            }),
          },
        },
        {
          'shamorZachor': {
            'sz:progress_by_id': json.encode({
              // review1 בוטל בכוונה — מיזוג פר-דף היה מחזיר אותו
              'ברכות': {
                '2': {'learn': true},
              },
            }),
          },
        },
      );

      final progress =
          json.decode(
                (merged['shamorZachor'] as Map)['sz:progress_by_id'] as String,
              )
              as Map<String, dynamic>;
      expect(progress.keys, containsAll(['ברכות', 'שבת']));
      expect(progress['ברכות']['2'], {'learn': true});
    });
  });

  group('תוספים', () {
    Map<String, dynamic> plugin(String id, String version) => {
      'installation': {'plugin_id': id, 'version': version},
      'files': {'main.js': 'sha256:abc'},
    };

    test('איחוד לפי plugin_id — רשומת החדש מנצחת בשלמותה', () {
      final merged = merge(
        {
          'plugins': [plugin('a', '1.0'), plugin('b', '1.0')],
        },
        {
          'plugins': [plugin('a', '2.0')],
        },
      );

      final plugins = (merged['plugins'] as List).cast<Map>();
      expect(plugins, hasLength(2));
      final a = plugins.firstWhere(
        (p) => (p['installation'] as Map)['plugin_id'] == 'a',
      );
      expect((a['installation'] as Map)['version'], '2.0');
    });
  });

  group('workspaces + includes', () {
    test('currentWorkspace מהחדש; includes הוא איחוד דגלים', () {
      final merged = merge(
        {
          'includes': {'bookmarks': true, 'notes': false},
          'workspaces': [
            {'id': 'w1', 'name': 'ישן'},
          ],
          'currentWorkspace': 'w1',
        },
        {
          'includes': {'notes': true},
          'workspaces': [
            {'id': 'w2', 'name': 'חדש'},
          ],
          'currentWorkspace': 'w2',
        },
      );

      expect(merged['includes'], {'bookmarks': true, 'notes': true});
      expect((merged['workspaces'] as List), hasLength(2));
      expect(merged['currentWorkspace'], 'w2');
      expect(merged['origin'], 'archive');
    });
  });
}

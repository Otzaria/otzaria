import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/migration/models/docx_text_cache_entry.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/docx_cache.dart';
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';

/// בדיקות ללוגיקת הזרקת-הכותרת של מטמון ה-docx. המטמון מפתוח לפי הקובץ
/// (לא לפי שם הספר), כך ששינוי-שם אינו פוסל את המטמון אך הכותרת מתעדכנת.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('withFreshDocxTitle', () {
    test('מחליף את שורת הכותרת בשם הנוכחי, שומר את שאר התוכן', () {
      const cached = '<h1>שם ישן</h1>\n<p>תוכן הספר</p>\nעוד שורה';
      final result = withFreshDocxTitle(cached, 'שם חדש');
      expect(result, '<h1>שם חדש</h1>\n<p>תוכן הספר</p>\nעוד שורה');
    });

    test('טקסט עם h1 בלבד (בלי שורות נוספות) מתעדכן', () {
      const cached = '<h1>ישן</h1>';
      expect(withFreshDocxTitle(cached, 'חדש'), '<h1>חדש</h1>');
    });

    test('טקסט שאינו פותח ב-h1 מוחזר כפי שהוא', () {
      const cached = '<p>בלי כותרת</p>\nשורה';
      expect(withFreshDocxTitle(cached, 'שם'), cached);
    });

    test('כותרת זהה משאירה את התוכן ללא שינוי מהותי', () {
      const cached = '<h1>אותו שם</h1>\nתוכן';
      expect(withFreshDocxTitle(cached, 'אותו שם'), cached);
    });
  });

  test('ממיר מחדש Markdown שנשמר במטמון לפני תיקון הקישורים וההערות', () async {
    final root = await Directory.systemTemp.createTemp('markdown-cache-');
    final holder = CacheDatabaseHolder.instance;
    addTearDown(() async {
      await holder.close();
      await root.delete(recursive: true);
    });
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      root.path,
    );
    expect(
      await AppPaths.resolveCacheDbPath(),
      path.join(root.path, 'cache.db'),
    );

    final file = await File(path.join(root.path, 'book.md')).writeAsString(
      'https://example.com/%40foo\n\n'
      'עברית[^ראשון] ושוב[^שני].\n\n'
      '[^שני]: תוכן שני\n\n'
      '[^ראשון]: תוכן ראשון\n',
    );
    final stat = await file.stat();
    final now = DateTime.now().millisecondsSinceEpoch;
    final repository = await holder.repository;
    await repository.upsertDocxTextCacheEntry(
      DocxTextCacheEntry(
        filePath: '${file.path}#markdown',
        fileSize: stat.size,
        lastModified: stat.modified.millisecondsSinceEpoch,
        converterVersion: 8,
        text:
            '<p><a href="https://example.com/%2540foo">קישור</a></p>\n'
            'תוכן שני\nתוכן ראשון',
        createdAt: now,
        accessedAt: now,
      ),
    );

    final html = await convertMarkdownWithCache(file, 'ספר');

    expect(html, contains('href="https://example.com/%40foo"'));
    expect(html, matches(RegExp('תוכן ראשון.*תוכן שני', dotAll: true)));

    // השמירה במטמון מסתיימת ברקע לאחר החזרת הפלט.
    await Future<void>.delayed(Duration.zero);
    final refreshed = await repository.getDocxTextCacheEntry(
      '${file.path}#markdown',
    );
    expect(refreshed?.converterVersion, 9);
  });
}

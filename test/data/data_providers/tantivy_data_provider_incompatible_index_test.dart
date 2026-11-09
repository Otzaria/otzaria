import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// סכמה לא תואמת חייבת להיחסם לפני הפתיחה, כדי שלא תיספר כאינדקס פגום.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('TantivyDataProvider — אינדקס בסכמה לא תואמת', () {
    late Directory root;
    late Directory indexDir;
    late List<String> log;
    late DebugPrintCallback originalDebugPrint;

    setUp(() async {
      if (!engineReady) return;
      log = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => log.add(message ?? '');

      root = Directory.systemTemp.createTempSync('otzaria_incompatible_idx_');
      indexDir = Directory(p.join(root.path, 'index'))..createSync();
      await _writeIncompatibleIndex(indexDir);

      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue(SettingsRepository.keyIndexPath, indexDir.path);
      AppPaths.debugOverrideDataRootPath(p.join(root.path, 'data'));
    });

    tearDown(() async {
      if (!engineReady) return;
      debugPrint = originalDebugPrint;
      await TantivyDataProvider.instance.dispose();
      AppPaths.debugOverrideDataRootPath(null);
      await Settings.clearCache();
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // ב-Windows המנוע עלול להחזיק קבצים פתוחים בסיום הטסט.
      }
    });

    test(
      'rebuild_required: אינדקס הדיסק אינו נפתח, ושני קוראים חולקים אתחול אחד',
      () async {
        final compatibility = await checkIndexCompatibility(
          path: indexDir.path,
        );
        expect(compatibility.status, 'rebuild_required');

        // הסינגלטון חי בין הטסטים — פתיחה מאולצת מכוונת אותו ל-fixture הזה.
        final provider = TantivyDataProvider.instance;
        await provider.reopenIndex(force: true);
        final engines = await Future.wait([provider.engine, provider.engine]);

        expect(identical(engines[0], engines[1]), isTrue);
        expect(provider.indexCompatibility?.status, 'rebuild_required');
        expect(provider.requiresManualReindex, isTrue);
        expect(provider.isTempFallback, isTrue);
        expect(provider.activeIndexPath, isNot(indexDir.path));

        // ניסיון פתיחה היה מותיר סנטינל כשל ומדווח panic — שניהם חייבים
        // להיעדר, כלומר האינדקס הלא-תואם לא נגע בדיסק כלל.
        expect(
          File(p.join(root.path, '.engine_init_started')).existsSync(),
          isFalse,
          reason: 'סנטינל הפתיחה נכתב — האינדקס הלא-תואם נפתח בכל זאת',
        );
        expect(
          log.where((line) => line.contains('Failed to initialize')),
          isEmpty,
        );
        expect(log.where((line) => line.contains('PanicException')), isEmpty);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'אחרי clear (מחיקת האינדקס) המנוע נפתח על הדיסק ואינו דורש rebuild',
      () async {
        final provider = TantivyDataProvider.instance;
        await provider.reopenIndex(force: true);
        expect(provider.isTempFallback, isTrue);

        await provider.clear();

        expect(provider.isTempFallback, isFalse);
        expect(provider.activeIndexPath, indexDir.path);
        expect(provider.requiresManualReindex, isFalse);
        expect(
          File(p.join(root.path, '.engine_init_started')).existsSync(),
          isFalse,
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });
}

/// מסיר שדה חובה מהסכמה ואת קובץ התאימות כדי לייצר אינדקס שאסור לפתוח.
Future<void> _writeIncompatibleIndex(Directory indexDir) async {
  final engine = await SearchEngine.newInstance(path: indexDir.path);
  await engine.addDocument(
    ordinal: 0,
    title: 'ספר',
    reference: 'ספר א',
    topics: '/ספר',
    text: 'בראשית ברא',
    segment: BigInt.one,
    isPdf: false,
    filePath: 'id:1',
  );
  await engine.commit();
  engine.dispose();

  File(p.join(indexDir.path, 'otzaria_index_meta.json')).deleteSync();
  final metaFile = File(p.join(indexDir.path, 'meta.json'));
  final meta = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
  final schema = meta['schema'] as List<dynamic>;
  schema.removeWhere(
    (field) => (field as Map<String, dynamic>)['name'] == 'text',
  );
  metaFile.writeAsStringSync(jsonEncode(meta));
}

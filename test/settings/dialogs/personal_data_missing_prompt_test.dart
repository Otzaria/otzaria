import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/settings/dialogs/personal_data_missing_prompt.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('personal_data_missing_');
    Hive.init(root.path);
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      p.join(root.path, 'databases'),
    );
    AppPaths.debugOverrideDataRootPath(root.path);
  });

  tearDown(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await Hive.close();
    await root.delete(recursive: true);
  });

  testWidgets(
    'מסדים אישיים שנמחקו מבחוץ — מוצע שחזור מגיבוי, ובהתקנה חדשה לא (issue #2610)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
      );
      Future<bool> promptAtStartup() async {
        await tester.runAsync(PersonalDataMissingPrompt.detect);
        unawaited(PersonalDataMissingPrompt.showIfNeeded());
        await tester.pumpAndSettle();
        return find.text('שחזר מגיבוי').evaluate().isNotEmpty;
      }

      // התקנה חדשה: עוד לא נטענה ספרייה, ואין מסדים.
      expect(await promptAtStartup(), isFalse);

      // נטענה ספרייה בעבר, והמסדים נמחקו כשהתוכנה הייתה סגורה.
      File(p.join(root.path, 'library_loaded.marker')).createSync();
      expect(await promptAtStartup(), isTrue);
      await tester.tap(find.text('המשך בלי לשחזר'));
      await tester.pumpAndSettle();
      expect(find.text('שחזר מגיבוי'), findsNothing);

      // העלייה הזו פתחה את המסדים מחדש, ולכן בעלייה הבאה אין הודעה.
      File(p.join(root.path, 'databases', 'user_state.db')).createSync();
      expect(await promptAtStartup(), isFalse);
    },
  );
}

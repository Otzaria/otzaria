import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/backup_service.dart';

import '../../helpers/memory_settings_cache.dart';

/// DD-30 (השלמה 3.11): ההגדרות שלשוניות המערכת והעיצוב קראו ב־build עוברות דרך
/// SettingsBloc. זרם השינויים מוזרק לבלוק ואופציונלי: בלעדיו הבלוק עובד כמו
/// קודם (בדיקות ומאגרים מדומים), ואיתו הוא רואה גם כתיבות שלא עברו דרכו.
void main() {
  late SettingsRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    repository = SettingsRepository();
  });

  SettingsBloc newBloc({Stream<String>? externalChanges}) {
    final bloc = SettingsBloc(
      repository: repository,
      initialSettings: repository.readSettings(),
      externalChanges: externalChanges,
      ensureFontLoaded: (_) async {},
    );
    addTearDown(bloc.close);
    return bloc;
  }

  group('בלי זרם שינויים', () {
    test('ברירות המחדל כמו בקריאה הישירה הקודמת', () {
      final state = newBloc().state;
      expect(state.autoSync, isTrue);
      expect(state.updateCheckFrequency, '');
      expect(state.restoreAllWindows, isFalse);
      expect(state.backupPath, '');
      expect(state.autoBackupFrequency, 'weekly');
      expect(state.backupRetentionProfile, '');
      expect(state.splitedView, isTrue);
      expect(state.libraryPath, '');
      expect(state.hebrewBooksPath, '');
      expect(state.backupIncludesAllSections, isTrue);
      expect(
        state.backupSections.keys,
        unorderedEquals(SettingsRepository.backupSectionKeys),
      );
    });

    test('ערכים שמורים נטענים למצב', () async {
      await Settings.setValue<bool>(SettingsRepository.keyAutoSync, false);
      await Settings.setValue<String>(
        SettingsRepository.keyAutoBackupFrequency,
        'monthly',
      );
      await Settings.setValue<bool>(SettingsRepository.keyBackupNotes, false);
      await Settings.setValue<bool>('key-splited-view', false);
      final state = newBloc().state;
      expect(state.autoSync, isFalse);
      expect(state.autoBackupFrequency, 'monthly');
      expect(state.backupIncludes(SettingsRepository.keyBackupNotes), isFalse);
      expect(state.backupIncludesAllSections, isFalse);
      expect(state.splitedView, isFalse);
    });

    test('אירועים נשמרים באותם מפתחות ומעדכנים את המצב', () async {
      final bloc = newBloc();
      bloc
        ..add(const UpdateAutoSync(false))
        ..add(const UpdateUpdateCheckFrequency('weekly'))
        ..add(const UpdateRestoreAllWindows(true))
        ..add(const UpdateBackupPath('C:/backups'))
        ..add(const UpdateAutoBackupFrequency('daily'))
        ..add(const UpdateBackupRetentionProfile('keepAll'))
        ..add(const UpdateSplitedView(false))
        ..add(
          const UpdateBackupSection(SettingsRepository.keyBackupPlugins, false),
        );
      await bloc.stream.firstWhere(
        (s) =>
            !s.backupIncludes(SettingsRepository.keyBackupPlugins) &&
            !s.splitedView,
      );

      expect(Settings.getValue<bool>(SettingsRepository.keyAutoSync), isFalse);
      expect(
        Settings.getValue<String>(SettingsRepository.keyUpdateCheckFrequency),
        'weekly',
      );
      expect(
        Settings.getValue<bool>(SettingsRepository.keyRestoreAllWindows),
        isTrue,
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyBackupPath),
        'C:/backups',
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyAutoBackupFrequency),
        'daily',
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyBackupRetentionProfile),
        'keepAll',
      );
      expect(Settings.getValue<bool>('key-splited-view'), isFalse);
      expect(BackupService.includesAllSections, isFalse);

      final state = bloc.state;
      expect(state.autoSync, isFalse);
      expect(state.updateCheckFrequency, 'weekly');
      expect(state.restoreAllWindows, isTrue);
      expect(state.backupPath, 'C:/backups');
      expect(state.autoBackupFrequency, 'daily');
      expect(state.backupRetentionProfile, 'keepAll');
      expect(state.backupIncludesAllSections, isFalse);
    });

    test('IncludeAllBackupSections מדליק את כל הסעיפים', () async {
      for (final key in SettingsRepository.backupSectionKeys) {
        await Settings.setValue<bool>(key, false);
      }
      final bloc = newBloc();
      expect(bloc.state.backupIncludesAllSections, isFalse);
      bloc.add(const IncludeAllBackupSections());
      await bloc.stream.firstWhere((s) => s.backupIncludesAllSections);
      expect(BackupService.includesAllSections, isTrue);
    });

    test('כתיבה ישירה ל־Settings לא מגיעה לבלוק', () async {
      final bloc = newBloc();
      final emitted = <SettingsState>[];
      final sub = bloc.stream.listen(emitted.add);
      addTearDown(sub.cancel);
      await Settings.setValue<bool>('key-splited-view', false);
      await pumpEventQueue();
      expect(emitted, isEmpty);
      expect(bloc.state.splitedView, isTrue);
    });
  });

  group('עם זרם שינויים מוזרק', () {
    late StreamController<String> changes;

    setUp(() {
      changes = StreamController<String>.broadcast();
      addTearDown(changes.close);
    });

    test('הקורא כותב key-splited-view: המצב מתעדכן', () async {
      final bloc = newBloc(externalChanges: changes.stream);
      expect(bloc.state.splitedView, isTrue);

      // כמו TextBookBloc._onToggleSplitView: ישר ל־Settings.
      await Settings.setValue<bool>('key-splited-view', false);
      changes.add('key-splited-view');

      final state = await bloc.stream.first;
      expect(state.splitedView, isFalse);
    });

    // q10 שאלה 21: לשונית הספרייה קוראת את הנתיבים מהבלוק. הם נכתבים מחוץ לו
    // (דיאלוג הגדרת הספרייה, LibraryBloc).
    test('נתיב הספרייה ונתיב היברובוקס שנכתבו מבחוץ מגיעים למצב', () async {
      final bloc = newBloc(externalChanges: changes.stream);

      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        'C:/otzaria/books',
      );
      changes.add(SettingsRepository.keyLibraryPath);
      expect((await bloc.stream.first).libraryPath, 'C:/otzaria/books');

      await Settings.setValue<String>(
        SettingsRepository.keyHebrewBooksPath,
        'D:/hebrewbooks',
      );
      changes.add(SettingsRepository.keyHebrewBooksPath);
      expect((await bloc.stream.first).hebrewBooksPath, 'D:/hebrewbooks');

      // ניקוי הנתיב (RemoveHebrewBooksPath) מוחק את המפתח.
      await Settings.setValue<String?>(
        SettingsRepository.keyHebrewBooksPath,
        null,
      );
      changes.add(SettingsRepository.keyHebrewBooksPath);
      expect((await bloc.stream.first).hebrewBooksPath, '');
    });

    test('ערכי נתיבים שמורים נטענים בבנייה', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        'C:/otzaria/books',
      );
      final state = newBloc().state;
      expect(state.libraryPath, 'C:/otzaria/books');
    });

    test('חלון אחר משנה סעיף גיבוי: המצב מתעדכן', () async {
      final bloc = newBloc(externalChanges: changes.stream);
      expect(bloc.state.backupIncludesAllSections, isTrue);

      await Settings.setValue<bool>(SettingsRepository.keyBackupHistory, false);
      changes.add(SettingsRepository.keyBackupHistory);

      final state = await bloc.stream.first;
      expect(
        state.backupIncludes(SettingsRepository.keyBackupHistory),
        isFalse,
      );
      expect(state.backupIncludesAllSections, isFalse);
    });

    test('שינוי שלא משנה את המצב לא נפלט', () async {
      final bloc = newBloc(externalChanges: changes.stream);
      final emitted = <SettingsState>[];
      final sub = bloc.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      // מפתח שאינו בבלוק (התקדמות שמור וזכור), ומפתח שנכתב באותו ערך.
      await Settings.setValue<String>('sz:progress_by_id', '{}');
      changes
        ..add('sz:progress_by_id')
        ..add(SettingsRepository.keyAutoSync);
      await pumpEventQueue();
      expect(emitted, isEmpty);
    });

    test('כתיבה של הבלוק עצמו נפלטת פעם אחת', () async {
      final bloc = newBloc(externalChanges: changes.stream);
      final emitted = <SettingsState>[];
      final sub = bloc.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      bloc.add(const UpdateAutoSync(false));
      await bloc.stream.firstWhere((s) => !s.autoSync);
      // ההד מקובץ ההגדרות, כמו ש־Hive.watch היה שולח.
      changes.add(SettingsRepository.keyAutoSync);
      await pumpEventQueue();

      expect(emitted, hasLength(1));
      expect(emitted.single.autoSync, isFalse);
    });

    test('סגירת הבלוק מפסיקה את ההאזנה', () async {
      final bloc = SettingsBloc(
        repository: repository,
        initialSettings: repository.readSettings(),
        externalChanges: changes.stream,
        ensureFontLoaded: (_) async {},
      );
      expect(changes.hasListener, isTrue);
      await bloc.close();
      expect(changes.hasListener, isFalse);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/utils/pending_reindex_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/index_freshness_warner.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

/// האזהרה הלא-חוסמת על דריפט תוכן (issue #828): התוצאה נפתחת תמיד,
/// האזהרה מוצגת רק על אי-התאמה ודאית, החתימה נקראת פר-ספר, והמטמון נפסל
/// בכל התחלפות דור (אינדקס/ספרייה) או שינוי בקובץ המקור.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  final warner = IndexFreshnessWarner.instance;
  late _FakeTantivyDataProvider provider;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    warner.resetForTesting();
    provider = _FakeTantivyDataProvider(_FakeSearchEngine());
    warner.providerResolver = () => provider;
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
  });
  tearDown(warner.resetForTesting);

  test('החתימה נקראת פר-ספר, פעם אחת לכל ספר', () async {
    // ה-API הממוקד מחליף את מפת הקורפוס המלאה: כל ספר נקרא בנפרד, ובדיקה
    // חוזרת של אותו ספר אינה פונה למנוע שוב.
    warner.debugBookVerifier = (_, _) async => true;

    for (var id = 1; id <= 3; id++) {
      await warner.warnIfContentDrifted(TextBook(id: id, title: 'ספר $id'));
    }
    await warner.warnIfContentDrifted(TextBook(id: 1, title: 'ספר 1'));

    expect(provider.fakeEngine.requestedPaths, ['id:1', 'id:2', 'id:3']);
  });

  test('ספר עם דריפט מזהיר פעם אחת בלבד', () async {
    final book = TextBook(id: 1, title: 'ספר');
    var verifierCalls = 0;
    final notifications = <String>[];
    warner.debugBookVerifier = (_, _) async {
      verifierCalls++;
      return false;
    };
    warner.debugNotifier = notifications.add;

    await warner.warnIfContentDrifted(book);
    await warner.warnIfContentDrifted(book);

    expect(verifierCalls, 1);
    expect(notifications, [LibraryMessages.searchResultContentDrifted]);
  });

  test('ספר טרי אינו מזהיר', () async {
    final notifications = <String>[];
    warner.debugBookVerifier = (_, _) async => true;
    warner.debugNotifier = notifications.add;

    await warner.warnIfContentDrifted(TextBook(id: 2, title: 'טרי'));

    expect(notifications, isEmpty);
  });

  for (final scenario in ['drift', 'fresh', 'invalidated']) {
    test('חיווי ושימור החלפה אחרי אימות חיפוש: $scenario', () async {
      final dir = await Directory.systemTemp.createTemp('freshness_pending');
      addTearDown(() async {
        PendingReindexStore.resetMemoryForTesting();
        await dir.delete(recursive: true);
      });
      provider.activeIndexPath = dir.path;
      provider.indexedFilePaths.add('id:1');
      final book = TextBook(id: 1, title: 'ספר');
      final library = Library(categories: [])..books.add(book);
      DataRepository.instance.library = Future.value(library);
      final repository = IndexingRepository(
        provider,
        indexUpdateMode: () => IndexUpdateMode.off,
      );
      final bloc = IndexingBloc(repository);
      addTearDown(bloc.close);
      final ready = bloc.stream.firstWhere((s) => s is IndexingComplete);
      bloc.add(CheckIndexStatus(library));
      await ready.timeout(const Duration(seconds: 2));

      final entered = Completer<void>();
      final gate = Completer<bool>();
      final notifications = <String>[];
      warner.debugBookVerifier = (_, _) {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      warner.debugNotifier = notifications.add;
      final first = warner.warnIfContentDrifted(book, indexingBloc: bloc);
      final second = warner.warnIfContentDrifted(book, indexingBloc: bloc);
      await entered.future;
      if (scenario == 'invalidated') {
        DataRepository.instance.library = Future.value(library);
      }
      gate.complete(scenario == 'fresh');
      await Future.wait([first, second]);
      final settled = Completer<void>();
      bloc.add(IndexingWorkBarrier(onSettled: settled.complete));
      await settled.future.timeout(const Duration(seconds: 2));

      final drift = scenario == 'drift';
      expect(
        bloc.state,
        drift ? isA<IndexingInitial>() : isA<IndexingComplete>(),
      );
      expect(provider.isIndexing.value, isFalse);
      expect(provider.indexedFilePaths, {'id:1'});
      expect(
        notifications,
        drift ? [LibraryMessages.searchResultContentDrifted] : isEmpty,
      );
      PendingReindexStore.resetMemoryForTesting();
      expect(
        await PendingReindexStore.forIndex(dir.path)!.load(),
        drift ? {'id:1'} : isEmpty,
      );
    });
  }

  group('מסירת דריפט למנהל אינדוקס מאוחר', () {
    late Directory dir;
    late TextBook book;
    late Library library;
    late _RecordingIndexingBloc bloc;

    Future<_RecordingIndexingBloc> createBloc({Library? statusLibrary}) async {
      final created = _RecordingIndexingBloc(
        IndexingRepository(
          provider,
          indexUpdateMode: () => IndexUpdateMode.off,
        ),
      );
      addTearDown(() async {
        if (!created.isClosed) await created.close();
      });
      final ready = created.stream.firstWhere((s) => s is IndexingComplete);
      created.add(CheckIndexStatus(statusLibrary ?? library));
      await ready.timeout(const Duration(seconds: 2));
      return created;
    }

    Future<void> settle(_RecordingIndexingBloc target) async {
      final settled = Completer<void>();
      target.add(IndexingWorkBarrier(onSettled: settled.complete));
      await settled.future.timeout(const Duration(seconds: 2));
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('freshness_late_bloc');
      PendingReindexStore.resetMemoryForTesting();
      addTearDown(() async {
        PendingReindexStore.resetMemoryForTesting();
        await dir.delete(recursive: true);
      });
      provider.activeIndexPath = dir.path;
      provider.indexedFilePaths.add('id:1');
      book = TextBook(id: 1, title: 'ספר');
      library = Library(categories: [])..books.add(book);
      DataRepository.instance.library = Future.value(library);
      bloc = await createBloc();
    });

    for (final timing in ['completed', 'in-flight']) {
      for (final drift in [true, false]) {
        test('$timing: null → bloc, drift=$drift', () async {
          var verifierCalls = 0;
          final notifications = <String>[];
          final entered = Completer<void>();
          final gate = Completer<bool>();
          warner.debugBookVerifier = (_, _) {
            verifierCalls++;
            if (!entered.isCompleted) entered.complete();
            return gate.future;
          };
          warner.debugNotifier = notifications.add;

          final first = warner.warnIfContentDrifted(book);
          await entered.future;
          if (timing == 'completed') {
            gate.complete(!drift);
            await first;
          }
          var joinedCompleted = false;
          final joined = warner
              .warnIfContentDrifted(book, indexingBloc: bloc)
              .then((_) {
                joinedCompleted = true;
              });
          final another = warner.warnIfContentDrifted(book, indexingBloc: bloc);
          if (timing == 'in-flight') {
            await Future<void>.delayed(Duration.zero);
            expect(joinedCompleted, isFalse);
            expect(verifierCalls, 1);
            gate.complete(!drift);
          }
          await Future.wait([first, joined, another]);
          await settle(bloc);

          expect(
            bloc.deferred,
            hasLength(drift ? 1 : 0),
            reason: 'קורא מאוחר עם מנהל אינדוקס מקבל את הדריפט פעם אחת',
          );
          expect(verifierCalls, 1);
          expect(provider.fakeEngine.requestedPaths, ['id:1']);
          expect(
            notifications,
            drift ? [LibraryMessages.searchResultContentDrifted] : isEmpty,
          );
          expect(
            bloc.state,
            drift ? isA<IndexingInitial>() : isA<IndexingComplete>(),
          );
          expect(provider.isIndexing.value, isFalse);
          expect(provider.indexedFilePaths, {'id:1'});
          PendingReindexStore.resetMemoryForTesting();
          expect(
            await PendingReindexStore.forIndex(dir.path)!.load(),
            drift ? {'id:1'} : isEmpty,
          );
          await warner.warnIfContentDrifted(book, indexingBloc: bloc);
          await settle(bloc);
          expect(bloc.deferred, hasLength(drift ? 1 : 0));
          expect(verifierCalls, 1);
        });
      }
    }

    for (final generation in ['library', 'engine', 'indexing']) {
      test('פסילה בזמן המתנה לספרייה לפני מסירה: $generation', () async {
        final libraryGate = Completer<Library>();
        DataRepository.instance.library = libraryGate.future;
        final notifications = <String>[];
        var verifierCalls = 0;
        warner.debugBookVerifier = (_, _) async {
          verifierCalls++;
          return false;
        };
        warner.debugNotifier = notifications.add;
        await warner.warnIfContentDrifted(book);

        var completed = false;
        final waiting = warner
            .warnIfContentDrifted(book, indexingBloc: bloc)
            .then((_) {
              completed = true;
            });
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        switch (generation) {
          case 'library':
            DataRepository.instance.library = Future.value(library);
          case 'engine':
            provider.replaceEngine(_FakeSearchEngine());
          case 'indexing':
            provider.isIndexing.value = true;
            provider.isIndexing.value = false;
        }
        libraryGate.complete(library);
        await waiting;
        await settle(bloc);

        expect(bloc.deferred, isEmpty);
        expect(bloc.state, isA<IndexingComplete>());
        expect(notifications, [LibraryMessages.searchResultContentDrifted]);
        expect(await PendingReindexStore.forIndex(dir.path)!.load(), isEmpty);

        await warner.warnIfContentDrifted(book, indexingBloc: bloc);
        await settle(bloc);
        expect(bloc.deferred, hasLength(1));
        expect(verifierCalls, 2);
        expect(notifications, hasLength(2));
        PendingReindexStore.resetMemoryForTesting();
        expect(await PendingReindexStore.forIndex(dir.path)!.load(), {'id:1'});
      });
    }

    test('סגירת מנהל בזמן ההמתנה אינה צורכת מסירה למחליפו', () async {
      final libraryGate = Completer<Library>();
      DataRepository.instance.library = libraryGate.future;
      var verifierCalls = 0;
      final notifications = <String>[];
      warner.debugBookVerifier = (_, _) async {
        verifierCalls++;
        return false;
      };
      warner.debugNotifier = notifications.add;
      await warner.warnIfContentDrifted(book);

      var completed = false;
      final waiting = warner
          .warnIfContentDrifted(book, indexingBloc: bloc)
          .then((_) {
            completed = true;
          });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      await bloc.close();
      libraryGate.complete(library);
      await waiting;
      expect(bloc.deferred, isEmpty);

      final replacement = await createBloc();
      await warner.warnIfContentDrifted(book, indexingBloc: replacement);
      await settle(replacement);
      await warner.warnIfContentDrifted(book, indexingBloc: replacement);
      await settle(replacement);
      expect(replacement.deferred, hasLength(1));
      expect(replacement.state, isA<IndexingInitial>());
      expect(verifierCalls, 1);
      expect(notifications, [LibraryMessages.searchResultContentDrifted]);
      PendingReindexStore.resetMemoryForTesting();
      expect(await PendingReindexStore.forIndex(dir.path)!.load(), {'id:1'});
    });

    test('מנהל מחליף טוען עבודה שנשמרה בדיסק בלי מסירה כפולה', () async {
      var verifierCalls = 0;
      final notifications = <String>[];
      warner.debugBookVerifier = (_, _) async {
        verifierCalls++;
        return false;
      };
      warner.debugNotifier = notifications.add;
      expect(
        await PendingReindexStore.forIndex(dir.path)!.save({'uid:99'}),
        isTrue,
      );
      await warner.warnIfContentDrifted(book, indexingBloc: bloc);
      await settle(bloc);
      expect(bloc.deferred, hasLength(1));
      await bloc.close();
      PendingReindexStore.resetMemoryForTesting();
      expect(
        await PendingReindexStore.forIndex(dir.path)!.load(),
        {'uid:99', 'id:1'},
      );

      final replacement = await createBloc(
        statusLibrary: Library(categories: []),
      );
      final pending = replacement.stream.firstWhere(
        (s) => s is IndexingInitial,
      );
      replacement.add(CheckIndexStatus(library));
      await pending.timeout(const Duration(seconds: 2));
      await warner.warnIfContentDrifted(book, indexingBloc: replacement);
      await settle(replacement);
      expect(replacement.deferred, isEmpty);
      expect(replacement.state, isA<IndexingInitial>());
      expect(verifierCalls, 1);
      expect(notifications, [LibraryMessages.searchResultContentDrifted]);
      PendingReindexStore.resetMemoryForTesting();
      expect(
        await PendingReindexStore.forIndex(dir.path)!.load(),
        {'uid:99', 'id:1'},
      );
    });
  });

  test(
    'ספר בלי חתימה באינדקס — לא ניתן לאימות, אין אזהרה (מסלול אמיתי)',
    () async {
      final notifications = <String>[];
      warner.debugNotifier = notifications.add;

      // בלי debugBookVerifier: textBookContentMatchesIndex האמיתי רץ ומחזיר
      // true מוקדם, כי המנוע המזויף מחזיר 0 ("לא ניתן לאימות").
      await warner.warnIfContentDrifted(TextBook(id: 3, title: 'לא באינדקס'));

      expect(notifications, isEmpty);
    },
  );

  test('סוף ריצת אינדוקס מאפס את המטמון — הספר נבדק מחדש', () async {
    final book = TextBook(id: 1, title: 'ספר');
    var verifierCalls = 0;
    warner.debugBookVerifier = (_, _) async {
      verifierCalls++;
      return true;
    };

    await warner.warnIfContentDrifted(book);
    provider.isIndexing.value = true;
    provider.isIndexing.value = false;
    await warner.warnIfContentDrifted(book);

    expect(verifierCalls, 2);
  });

  test('reopen (החלפת ה-Future של המנוע) מאפס את המטמון', () async {
    final book = TextBook(id: 1, title: 'ספר');
    var verifierCalls = 0;
    warner.debugBookVerifier = (_, _) async {
      verifierCalls++;
      return true;
    };

    await warner.warnIfContentDrifted(book);
    provider.replaceEngine(_FakeSearchEngine());
    await warner.warnIfContentDrifted(book);

    expect(verifierCalls, 2);
  });

  test('רענון ספרייה בלי שום אות אינדוקס מאפס את המטמון', () async {
    final book = TextBook(id: 1, title: 'ספר');
    var verifierCalls = 0;
    warner.debugBookVerifier = (_, _) async {
      verifierCalls++;
      return true;
    };

    await warner.warnIfContentDrifted(book);
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    await warner.warnIfContentDrifted(book);

    expect(verifierCalls, 2);
  });

  group('פסילת מטמון בזמן ההמתנה', () {
    late TextBook book;
    late Completer<bool> gate;
    late List<String> notifications;

    setUp(() {
      book = TextBook(id: 1, title: 'ספר');
      gate = Completer<bool>();
      notifications = [];
      warner.debugBookVerifier = (_, _) => gate.future;
      warner.debugNotifier = notifications.add;
    });

    test('החלפת ספרייה באמצע ההמתנה מבטלת את התוצאה הישנה', () async {
      // רגרסיה: ה-epoch לבדו לא הגן, כי החלפת ה-Future אינה מודיעה ל-warner
      // והיא מזוהה רק בכניסה הבאה לבדיקה.
      final pending = warner.warnIfContentDrifted(book);
      DataRepository.instance.library = Future.value(
        Library(categories: const []),
      );
      gate.complete(false);
      await pending;

      expect(notifications, isEmpty, reason: 'תוצאה מדור ישן אינה מוצגת');

      // ולא נצרבה: בדיקה חדשה של אותו ספר רצה במלואה ומזהירה.
      warner.debugBookVerifier = (_, _) async => false;
      await warner.warnIfContentDrifted(book);
      expect(notifications, [LibraryMessages.searchResultContentDrifted]);
    });

    test('מעבר isIndexing באמצע ההמתנה מבטל את התוצאה הישנה', () async {
      // רגרסיה: זהויות ה-Future אינן משתנות בריצת אינדוקס, ולכן ההשוואה
      // מולן לבדה לא הגנה — נדרש מונה שעולה בכל פסילת מטמון.
      final pending = warner.warnIfContentDrifted(book);
      provider.isIndexing.value = true;
      provider.isIndexing.value = false;
      gate.complete(false);
      await pending;

      expect(notifications, isEmpty, reason: 'תוצאה מדור ישן אינה מוצגת');

      warner.debugBookVerifier = (_, _) async => false;
      await warner.warnIfContentDrifted(book);
      expect(notifications, [LibraryMessages.searchResultContentDrifted]);
    });

    test('reopen באמצע ההמתנה מבטל את התוצאה הישנה', () async {
      final pending = warner.warnIfContentDrifted(book);
      provider.replaceEngine(_FakeSearchEngine());
      gate.complete(false);
      await pending;

      expect(notifications, isEmpty);

      warner.debugBookVerifier = (_, _) async => false;
      await warner.warnIfContentDrifted(book);
      expect(notifications, [LibraryMessages.searchResultContentDrifted]);
    });
  });

  test('אינדוקס פעיל לכל אורך הבדיקה אינו מזהיר ואינו נצרב', () async {
    // רגרסיה: כשהערך כבר true בכניסה אין מעבר, ולכן ה-token נשאר תקף —
    // והבדיקה קראה אינדקס שבאמצע בנייה והזהירה לשווא.
    final book = TextBook(id: 1, title: 'ספר');
    final notifications = <String>[];
    warner.debugBookVerifier = (_, _) async => false;
    warner.debugNotifier = notifications.add;

    provider.isIndexing.value = true;
    await warner.warnIfContentDrifted(book);

    expect(notifications, isEmpty, reason: 'אין השוואה מול אינדקס בבנייה');
    expect(provider.fakeEngine.requestedPaths, isEmpty);

    // אחרי סיום האינדוקס אותו ספר נבדק כרגיל.
    provider.isIndexing.value = false;
    await warner.warnIfContentDrifted(book);

    expect(notifications, [LibraryMessages.searchResultContentDrifted]);
  });

  test('אינדוקס שמתחיל באמצע ההמתנה מבטל את התוצאה', () async {
    final book = TextBook(id: 1, title: 'ספר');
    final gate = Completer<bool>();
    final notifications = <String>[];
    warner.debugBookVerifier = (_, _) => gate.future;
    warner.debugNotifier = notifications.add;

    final pending = warner.warnIfContentDrifted(book);
    provider.isIndexing.value = true;
    gate.complete(false);
    await pending;

    expect(notifications, isEmpty);
  });

  test('שתי בדיקות מקבילות לאותו ספר מתאחדות לריצה אחת', () async {
    // רגרסיה: הרשומה נכנסת למטמון רק בסוף הבדיקה, ולכן שתי פתיחות מקבילות
    // גיבבו את הספר פעמיים והציגו שתי אזהרות.
    final book = TextBook(id: 1, title: 'ספר');
    final gate = Completer<bool>();
    var verifierCalls = 0;
    final notifications = <String>[];
    warner.debugBookVerifier = (_, _) {
      verifierCalls++;
      return gate.future;
    };
    warner.debugNotifier = notifications.add;

    final first = warner.warnIfContentDrifted(book);
    final second = warner.warnIfContentDrifted(book);
    gate.complete(false);
    await Future.wait([first, second]);

    expect(verifierCalls, 1, reason: 'הספר גובב פעם אחת');
    expect(provider.fakeEngine.requestedPaths, ['id:1']);
    expect(notifications, [LibraryMessages.searchResultContentDrifted]);
  });

  test('כשל בריצה משותפת נבלע גם אצל הקורא המצטרף', () async {
    // רגרסיה: הקורא המצטרף קיבל את ה-Future המשותף ב-return בלי await —
    // השגיאה עקפה את ה-try שלו והפכה ל-async error גלובלי.
    final book = TextBook(id: 1, title: 'ספר');
    final gate = Completer<bool>();
    // ההמתנה לכניסה ל-verifier מבטיחה שיש מאזין ל-gate לפני השגיאה,
    // אחרת היא נזקפת כ-unhandled לפני שהמסלול הגיע אליה בכלל.
    final entered = Completer<void>();
    warner.debugBookVerifier = (_, _) {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };

    final first = warner.warnIfContentDrifted(book);
    final second = warner.warnIfContentDrifted(book);
    await entered.future;
    gate.completeError(StateError('verification failed'));
    // שני הקוראים משלימים בלי throw.
    await Future.wait([first, second]);

    // והכשל לא נצרב: קריאה מאוחרת מנסה מחדש ומצליחה להזהיר.
    final notifications = <String>[];
    warner.debugNotifier = notifications.add;
    warner.debugBookVerifier = (_, _) async => false;
    await warner.warnIfContentDrifted(book);
    expect(notifications, [LibraryMessages.searchResultContentDrifted]);
  });

  test('כשל בקריאת החתימה אינו נצרב — ניסיון חוזר בפתיחה הבאה', () async {
    final book = TextBook(id: 1, title: 'ספר');
    provider.fakeEngine.failuresBeforeSuccess = 1;
    final notifications = <String>[];
    warner.debugBookVerifier = (_, _) async => false;
    warner.debugNotifier = notifications.add;

    await warner.warnIfContentDrifted(book);
    expect(notifications, isEmpty);

    await warner.warnIfContentDrifted(book);
    expect(notifications, [LibraryMessages.searchResultContentDrifted]);
  });

  group('revision של קובץ מקור', () {
    late Directory dir;
    late File sourceFile;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('freshness_revision');
      sourceFile = File('${dir.path}/book.txt')..writeAsStringSync('שורה');
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // ignore
      }
    });

    test('עריכת קובץ המקור מחייבת בדיקה מחדש בלי דור חדש', () async {
      // רגרסיה: ספר file-backed נקרא ישירות מהדיסק, ואין רענון ספרייה
      // שמסמן עריכה חיצונית — המטמון היה מחזיר "תקין" לנצח.
      final book = TextBook(id: 1, title: 'ספר', filePath: sourceFile.path);
      var verifierCalls = 0;
      warner.debugBookVerifier = (_, _) async {
        verifierCalls++;
        return true;
      };

      await warner.warnIfContentDrifted(book);
      expect(verifierCalls, 1);

      await warner.warnIfContentDrifted(book);
      expect(verifierCalls, 1, reason: 'בלי שינוי בקובץ — מהמטמון');

      sourceFile.writeAsStringSync('שורה ערוכה וארוכה יותר');
      await warner.warnIfContentDrifted(book);

      expect(
        verifierCalls,
        2,
        reason: 'שינוי בקובץ פוסל את המטמון בלי engine/library חדשים',
      );
    });

    test('שינוי הקובץ בזמן האימות מבטל את התוצאה הישנה', () async {
      // רגרסיה: ה-revision נלכד בכניסה אך לא נבדק שוב בסוף — continuation
      // ישן כתב revision ישן והציג אזהרה שכבר אינה נכונה לתוכן הנוכחי.
      final book = TextBook(id: 1, title: 'ספר', filePath: sourceFile.path);
      final gate = Completer<bool>();
      final verifying = Completer<void>();
      final notifications = <String>[];
      warner.debugBookVerifier = (_, _) {
        verifying.complete();
        return gate.future;
      };
      warner.debugNotifier = notifications.add;

      final pending = warner.warnIfContentDrifted(book);
      // ה-revision נלכד ב-stat אסינכרוני; כתיבה לפני שהאימות התחיל הייתה
      // נלכדת כ-revision ה"ישן" והבדיקה לא הייתה בודקת דבר.
      await verifying.future;
      sourceFile.writeAsStringSync('תוכן חדש שנכתב באמצע האימות');
      gate.complete(false);
      await pending;

      expect(notifications, isEmpty, reason: 'תוצאה מול תוכן ישן אינה מוצגת');

      // ולא נצרבה: פתיחה חדשה בודקת את ה-revision החדש ומזהירה.
      var checkedAgain = false;
      warner.debugBookVerifier = (_, _) async {
        checkedAgain = true;
        return false;
      };
      await warner.warnIfContentDrifted(book);
      expect(checkedAgain, isTrue);
      expect(notifications, [LibraryMessages.searchResultContentDrifted]);
    });

    test('ספר בלי קובץ מקור נשמר במטמון כרגיל', () async {
      var verifierCalls = 0;
      warner.debugBookVerifier = (_, _) async {
        verifierCalls++;
        return true;
      };
      final book = TextBook(id: 9, title: 'ספר DB');

      await warner.warnIfContentDrifted(book);
      await warner.warnIfContentDrifted(book);

      expect(verifierCalls, 1);
    });
  });

  group('אינטגרציה מול המנוע האמיתי', () {
    late Directory indexDir;
    late SearchEngine engine;
    const bookText = '<h1>ספר</h1>\nשורה ראשונה של תוכן\nשורה שנייה';

    setUp(() async {
      if (!engineReady) return;
      indexDir = Directory.systemTemp.createTempSync('freshness_warner');
      engine = await SearchEngine.newInstance(path: indexDir.path);
    });

    tearDown(() {
      if (!engineReady) return;
      try {
        indexDir.deleteSync(recursive: true);
      } on FileSystemException {
        // ב-Windows המנוע עדיין מחזיק קבצים פתוחים; אין להפיל את הריצה.
      }
    });

    Future<void> indexBook(String text) async {
      await engine.addTextBook(
        title: 'ספר',
        topics: '/root/ספר',
        filePath: 'id:1',
        text: text,
        textStorage: TextStorage.inIndex,
      );
      await engine.commit();
    }

    test('אינדוקס → getBookTextFingerprint → שינוי תוכן מזוהה', () async {
      await indexBook(bookText);

      // ה-API הממוקד — זה שהאזהרה קוראת בפועל — ובאותו נשימה גם parity
      // מול הגרסה האסינכרונית שהאימות משתמש בה.
      final indexed = await engine.getBookTextFingerprint(filePath: 'id:1');
      expect(
        indexed,
        await computeContentFingerprintBytes(text: utf8Bytes(bookText)),
        reason: 'החתימה באינדקס זהה לחישוב האסינכרוני על תוכן הספר',
      );
      expect(
        indexed,
        computeContentFingerprint(text: bookText),
        reason: 'parity בין המסלול הסינכרוני לאסינכרוני',
      );

      const editedText = '$bookText\nשורה שנוספה בעריכה';
      expect(
        indexed,
        isNot(
          await computeContentFingerprintBytes(text: utf8Bytes(editedText)),
        ),
        reason: 'תוכן שהשתנה אינו תואם את החתימה הישנה',
      );

      await engine.deleteDocumentsByFilePath(filePath: 'id:1');
      await indexBook(editedText);
      expect(
        await engine.getBookTextFingerprint(filePath: 'id:1'),
        await computeContentFingerprintBytes(text: utf8Bytes(editedText)),
      );
    }, skip: !engineReady);

    test('ספר שאינו באינדקס מוכרע "לא ניתן לאימות" (0)', () async {
      await indexBook(bookText);
      expect(
        await engine.getBookTextFingerprint(filePath: 'id:404'),
        BigInt.zero,
      );
    }, skip: !engineReady);
  });
}

Uint8List utf8Bytes(String text) =>
    Uint8List.fromList(const Utf8Encoder().convert(text));

class _RecordingIndexingBloc extends IndexingBloc {
  _RecordingIndexingBloc(IndexingRepository repository) : super(repository);

  final List<DeferIndexing> deferred = [];

  @override
  void add(IndexingEvent event) {
    if (event is DeferIndexing) deferred.add(event);
    super.add(event);
  }
}

class _FakeSearchEngine implements SearchEngine {
  final List<String> requestedPaths = [];
  final Map<String, BigInt> textFingerprints = {};
  int failuresBeforeSuccess = 0;

  @override
  Future<BigInt> getBookTextFingerprint({required String filePath}) {
    requestedPaths.add(filePath);
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      return Future.error(StateError('engine down'));
    }
    return Future.value(textFingerprints[filePath] ?? BigInt.zero);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTantivyDataProvider implements TantivyDataProvider {
  _FakeTantivyDataProvider(this.fakeEngine) {
    engine = Future.value(fakeEngine);
  }

  _FakeSearchEngine fakeEngine;

  @override
  late Future<SearchEngine> engine;

  @override
  ValueNotifier<bool> isIndexing = ValueNotifier(false);

  @override
  String? activeIndexPath;

  @override
  final Set<String> indexedFilePaths = {};

  @override
  bool get isEconomyIndexing => false;

  @override
  bool get requiresManualReindex => false;

  /// מדמה reopen: המנוע (וזהות ה-Future) מוחלפים, כמו ב-_doReopen האמיתי.
  void replaceEngine(_FakeSearchEngine next) {
    fakeEngine = next;
    engine = Future.value(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

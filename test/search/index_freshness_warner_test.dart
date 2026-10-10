import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
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
        catalogueOrder: 5,
        generationOrder: 5,
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

  /// מדמה reopen: המנוע (וזהות ה-Future) מוחלפים, כמו ב-_doReopen האמיתי.
  void replaceEngine(_FakeSearchEngine next) {
    fakeEngine = next;
    engine = Future.value(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

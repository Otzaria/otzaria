import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:path/path.dart' as p;

import '../helpers/memory_settings_cache.dart';

void main() {
  group('TextBookPerBookSettings JSON', () {
    test('isTanach שורד round-trip ומושמט כשהוא null', () {
      final settings = TextBookPerBookSettings(
        removePunctuation: true,
        isTanach: true,
      );
      final restored = TextBookPerBookSettings.fromJson(settings.toJson());
      expect(restored.isTanach, isTrue);
      expect(restored.removePunctuation, isTrue);

      final withoutFlag = TextBookPerBookSettings(removePunctuation: true);
      expect(withoutFlag.toJson().containsKey('isTanach'), isFalse);
    });

    test('round-trip שומר את כל השדות כולל continuousReadingMode', () {
      final original = TextBookPerBookSettings(
        fontSize: 22.5,
        commentatorsBelow: true,
        removeNikud: false,
        removePunctuation: true,
        continuousReadingMode: true,
      );

      final restored = TextBookPerBookSettings.fromJson(original.toJson());

      expect(restored.fontSize, 22.5);
      expect(restored.commentatorsBelow, isTrue);
      expect(restored.removeNikud, isFalse);
      expect(restored.removePunctuation, isTrue);
      expect(restored.continuousReadingMode, isTrue);
    });

    test('toJson משמיט שדות null', () {
      final settings = TextBookPerBookSettings(continuousReadingMode: true);
      final json = settings.toJson();

      expect(json.containsKey('continuousReadingMode'), isTrue);
      expect(json.containsKey('fontSize'), isFalse);
      expect(json.containsKey('commentatorsBelow'), isFalse);
      expect(json.containsKey('removeNikud'), isFalse);
      expect(json.containsKey('removePunctuation'), isFalse);
    });

    test('fromJson עם שדה חסר מחזיר null עבור continuousReadingMode', () {
      // תאימות לאחור: הגדרות שנשמרו לפני הפיצ'ר אינן מכילות את השדה.
      final restored = TextBookPerBookSettings.fromJson({
        'fontSize': 18.0,
        'removeNikud': true,
      });
      expect(restored.continuousReadingMode, isNull);
      expect(restored.fontSize, 18.0);
      expect(restored.removeNikud, isTrue);
    });

    test('round-trip שומר את רוחבי הטורים בצורת הדף', () {
      final original = TextBookPerBookSettings(
        pageShapeLeftWidth: 240.5,
        pageShapeRightWidth: 180.0,
        pageShapeBottomHeight: 300.0,
        pageShapeBottomLeftWidth: 400.0,
      );

      final restored = TextBookPerBookSettings.fromJson(original.toJson());

      expect(restored.pageShapeLeftWidth, 240.5);
      expect(restored.pageShapeRightWidth, 180.0);
      expect(restored.pageShapeBottomHeight, 300.0);
      expect(restored.pageShapeBottomLeftWidth, 400.0);
    });

    test('toJson משמיט רוחבי טורים null', () {
      final settings = TextBookPerBookSettings(pageShapeLeftWidth: 100.0);
      final json = settings.toJson();

      expect(json.containsKey('pageShapeLeftWidth'), isTrue);
      expect(json.containsKey('pageShapeRightWidth'), isFalse);
      expect(json.containsKey('pageShapeBottomHeight'), isFalse);
      expect(json.containsKey('pageShapeBottomLeftWidth'), isFalse);
    });

    test('fromJson מקבל גם ערכי רוחב שלמים (int) מ-JSON', () {
      // הגנה מפני ערכים שנשמרו כ-int (JSON אינו מבחין בין int ל-double).
      final restored = TextBookPerBookSettings.fromJson({
        'pageShapeLeftWidth': 200,
        'pageShapeBottomHeight': 250,
      });
      expect(restored.pageShapeLeftWidth, 200.0);
      expect(restored.pageShapeBottomHeight, 250.0);
      expect(restored.pageShapeRightWidth, isNull);
    });

    test('copyWith משמר שדות קיימים ומעדכן רק את שניתנו', () {
      final base = TextBookPerBookSettings(
        fontSize: 20.0,
        removeNikud: true,
        pageShapeLeftWidth: 100.0,
      );

      // עדכון רק רוחבי הטורים - שאר השדות נשמרים
      final updated = base.copyWith(
        pageShapeLeftWidth: 150.0,
        pageShapeRightWidth: 90.0,
      );

      expect(updated.fontSize, 20.0);
      expect(updated.removeNikud, isTrue);
      expect(updated.pageShapeLeftWidth, 150.0);
      expect(updated.pageShapeRightWidth, 90.0);
      expect(updated.pageShapeBottomHeight, isNull);
    });

    test('round-trip שומר את רשימת המפרשים הנבחרים', () {
      final original = TextBookPerBookSettings(
        activeCommentators: const ['רש"י', 'תוספות'],
      );

      final restored = TextBookPerBookSettings.fromJson(original.toJson());

      expect(restored.activeCommentators, ['רש"י', 'תוספות']);
    });

    test('רשימת מפרשים ריקה שורדת round-trip (בחירה שבוטלה)', () {
      // בחירה ריקה היא מצב מכוון (המשתמש הסיר את כל המפרשים) ולכן נשמרת
      // ולא נחשבת כ-null.
      final settings = TextBookPerBookSettings(activeCommentators: const []);
      final json = settings.toJson();
      expect(json.containsKey('activeCommentators'), isTrue);

      final restored = TextBookPerBookSettings.fromJson(json);
      expect(restored.activeCommentators, isEmpty);
    });

    test('toJson משמיט activeCommentators כשהוא null', () {
      final settings = TextBookPerBookSettings(fontSize: 18.0);
      expect(settings.toJson().containsKey('activeCommentators'), isFalse);
    });

    test('copyWith משמר את activeCommentators כשלא ניתן', () {
      final base = TextBookPerBookSettings(activeCommentators: const ['רש"י']);
      final updated = base.copyWith(fontSize: 20.0);
      expect(updated.activeCommentators, ['רש"י']);
      expect(updated.fontSize, 20.0);
    });

    test('continuousReadingMode=false שורד round-trip', () {
      // toJson משמיט רק null (לא false). אם בעתיד מישהו ירצה לשמור
      // false במפורש — הוא חייב לעבוד. _savePerBookSettingsDirectly
      // הוא זה שמחליט אם להמיר false ל-null (אופטימיזציה של אחסון),
      // לא ה-JSON עצמו.
      final settings = TextBookPerBookSettings(continuousReadingMode: false);
      final json = settings.toJson();
      expect(json['continuousReadingMode'], isFalse);

      final restored = TextBookPerBookSettings.fromJson(json);
      expect(restored.continuousReadingMode, isFalse);
    });
  });

  group('PerBookSettings.bookKey — מפתח ייחודי לספר', () {
    test('ספר אישי וספר רשמי באותו שם מקבלים מפתחות נפרדים', () {
      final official = TextBook(title: 'ספר', categoryId: 1);
      final user = TextBook(title: 'ספר', categoryId: 1, isUserBook: true);

      expect(
        PerBookSettings.bookKey(official),
        isNot(PerBookSettings.bookKey(user)),
      );
    });

    test('שני ספרי טקסט באותו שם בקטגוריות שונות נפרדים', () {
      final a = TextBook(title: 'ספר', categoryId: 1);
      final b = TextBook(title: 'ספר', categoryId: 2);

      expect(PerBookSettings.bookKey(a), isNot(PerBookSettings.bookKey(b)));
    });

    test('ספרי PDF באותו שם בנתיבים שונים נפרדים (מפתוח לפי path)', () {
      final a = PdfBook(title: 'ספר', path: '/a/book.pdf');
      final b = PdfBook(title: 'ספר', path: '/b/book.pdf');

      expect(PerBookSettings.bookKey(a), isNot(PerBookSettings.bookKey(b)));
    });

    test('נתיבים שונים בעלי sanitize זהה עדיין נפרדים (a_b מול a/b)', () {
      // ללא hash, _sanitizeBookName היה ממיר את שניהם לאותו שם קובץ.
      final a = PdfBook(title: 'ספר', path: r'C:\library\a_b.pdf');
      final b = PdfBook(title: 'ספר', path: r'C:\library\a\b.pdf');

      expect(PerBookSettings.bookKey(a), isNot(PerBookSettings.bookKey(b)));
    });

    test('אותו ספר מחזיר מפתח יציב', () {
      final book = TextBook(title: 'ספר', categoryId: 1);
      expect(
        PerBookSettings.bookKey(book),
        equals(PerBookSettings.bookKey(book)),
      );
    });
  });

  group('PdfBookPerBookSettings — שמירה/טעינה בפועל', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('per_book_test');
      AppPaths.debugOverrideDataRootPath(tempDir.path);
    });

    tearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<File> writeLegacy(String title, Map<String, dynamic> json) async {
      final dir = Directory(p.join(tempDir.path, 'per_book_settings'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'settings_$title.json'));
      await file.writeAsString(jsonEncode(json));
      return file;
    }

    test('שני נתיבים בעלי sanitize זהה נשמרים ונטענים בנפרד', () async {
      final a = PdfBook(title: 'ספר', path: r'C:\library\a_b.pdf');
      final b = PdfBook(title: 'ספר', path: r'C:\library\a\b.pdf');

      await PdfBookPerBookSettings(zoom: 1.5).save(a);
      await PdfBookPerBookSettings(zoom: 2.5).save(b);

      expect((await PdfBookPerBookSettings.load(a))?.zoom, 1.5);
      expect((await PdfBookPerBookSettings.load(b))?.zoom, 2.5);
    });

    test('שני ספרים באותו שם יורשים legacy; איפוס אחד לא פוגע באחר', () async {
      await writeLegacy('ספר', {'zoom': 3.0});

      final a = PdfBook(title: 'ספר', path: '/a/ספר.pdf');
      final b = PdfBook(title: 'ספר', path: '/b/ספר.pdf');

      // שניהם יורשים את ה-legacy (copy, לא rename)
      expect((await PdfBookPerBookSettings.load(a))?.zoom, 3.0);
      expect((await PdfBookPerBookSettings.load(b))?.zoom, 3.0);

      // איפוס a — b עדיין שומר את ההגדרה הישנה (ה-legacy לא נמחק)
      await PdfBookPerBookSettings.delete(a);
      expect((await PdfBookPerBookSettings.load(a))?.zoom, isNull);
      expect((await PdfBookPerBookSettings.load(b))?.zoom, 3.0);
    });

    test('איפוס אינו "מתחייה" בפתיחה הבאה (tombstone)', () async {
      await writeLegacy('ספר', {'zoom': 4.0});
      final a = PdfBook(title: 'ספר', path: '/a/ספר.pdf');

      expect((await PdfBookPerBookSettings.load(a))?.zoom, 4.0);
      await PdfBookPerBookSettings.delete(a);
      // טעינה חוזרת לא משחזרת מ-legacy
      expect((await PdfBookPerBookSettings.load(a))?.zoom, isNull);
    });

    test('שמירות מקבילות על אותו ספר אינן נדרסות (תור נעילה משותף)', () async {
      // בלי סדרוּל load→merge→save, השמירה השנייה קוראת existing לפני
      // שהראשונה כתבה, ודורסת את zoom. התור מבטיח שכל שדה משתלב.
      final book = PdfBook(title: 'ספר', path: '/a/ספר.pdf');

      await Future.wait([
        PdfBookPerBookSettings(zoom: 1.5).save(book),
        PdfBookPerBookSettings(activeCommentators: const ['רש"י']).save(book),
      ]);

      final loaded = await PdfBookPerBookSettings.load(book);
      expect(loaded?.zoom, 1.5);
      expect(loaded?.activeCommentators, ['רש"י']);
    });
  });

  group('cleanupRedundantSettings — הסרת שדות מיותרים', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('per_book_cleanup');
      AppPaths.debugOverrideDataRootPath(tempDir.path);
    });

    tearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    // כותב קובץ legacy (שם מ-sanitize של כותרת, לא hash) ישירות לתיקייה.
    Future<File> writeLegacy(String name, Map<String, dynamic> json) async {
      final dir = Directory(p.join(tempDir.path, 'per_book_settings'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'settings_$name.json'));
      await file.writeAsString(jsonEncode(json));
      return file;
    }

    Map<String, dynamic>? readJson(File f) => f.existsSync()
        ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
        : null;

    Future<void> runCleanup({
      bool defaultContinuous = false,
      bool defaultRemovePunctuation = false,
    }) => PerBookSettings.cleanupRedundantSettings(
      defaultFontSize: 16,
      defaultRemoveNikud: false,
      defaultRemovePunctuation: defaultRemovePunctuation,
      defaultShowSplitView: true,
      defaultContinuousReadingMode: defaultContinuous,
    );

    // מפתחות דמויי-production: bookKey אמיתי → קובץ נשמר בשם hash (SHA-1).
    test('override ששווה לברירת המחדל מוסר גם כשיש שדה פר-ספר אחר', () async {
      // הבאג שתוקן: השדה נשאר בקובץ בגלל activeCommentators והמשיך לעקוף
      // את ברירת המחדל בשינוי גלובלי עתידי.
      const key = 'o__1__בראשית';
      await PerBookSettings.saveSettings(key, {
        'continuousReadingMode': true,
        'activeCommentators': ['רש"י'],
      });

      await runCleanup(defaultContinuous: true);

      final json = await PerBookSettings.loadSettings(key);
      expect(json, isNotNull);
      expect(json!.containsKey('continuousReadingMode'), isFalse);
      expect(json['activeCommentators'], ['רש"י']);
    });

    test('override ששונה מברירת המחדל נשמר', () async {
      const key = 'o__2__שמות';
      await PerBookSettings.saveSettings(key, {'continuousReadingMode': true});
      await runCleanup(defaultContinuous: false);
      expect(
        (await PerBookSettings.loadSettings(key))?['continuousReadingMode'],
        isTrue,
      );
    });

    test('קובץ שכל שדותיו זהים לברירת המחדל נמחק', () async {
      const key = 'o__3__ויקרא';
      await PerBookSettings.saveSettings(key, {
        'continuousReadingMode': true,
        'removeNikud': false,
      });
      await runCleanup(defaultContinuous: true);
      expect(await PerBookSettings.loadSettings(key), isNull);
    });

    test('removePunctuation ששונה מברירת המחדל הגלובלית נשמר', () async {
      const key = 'o__4__במדבר';
      await PerBookSettings.saveSettings(key, {'removePunctuation': true});
      await runCleanup();
      expect(
        (await PerBookSettings.loadSettings(key))?['removePunctuation'],
        isTrue,
      );
    });

    test('removePunctuation=false מוסר כשברירת המחדל הגלובלית כבויה', () async {
      const key = 'o__6__במדבר ב';
      await PerBookSettings.saveSettings(key, {'removePunctuation': false});
      await runCleanup();
      expect(await PerBookSettings.loadSettings(key), isNull);
    });

    test(
      'removePunctuation=true בספר רגיל מוסר כשהברירה הגלובלית נדלקת',
      () async {
        // ה-override נעשה מיותר — חייב להימחק כדי שהספר יירש שינוי עתידי
        // של הברירה הגלובלית בחזרה ל-false.
        const key = 'o__7__במדבר ג';
        await PerBookSettings.saveSettings(key, {'removePunctuation': true});
        await runCleanup(defaultRemovePunctuation: true);
        expect(await PerBookSettings.loadSettings(key), isNull);
      },
    );

    test(
      'override פיסוק של תנ"ך שורד ברירה גלובלית דלוקה (דגל isTanach)',
      () async {
        // בתנ"ך הברירה האפקטיבית תמיד false — override true הוא אמיתי ונשמר.
        const key = 'o__8__תהלים';
        await PerBookSettings.saveSettings(key, {
          'removePunctuation': true,
          'isTanach': true,
        });
        await runCleanup(defaultRemovePunctuation: true);
        final json = await PerBookSettings.loadSettings(key);
        expect(json?['removePunctuation'], isTrue);
        expect(json?['isTanach'], isTrue);
      },
    );

    test(
      'בתנ"ך removePunctuation=false מיותר גם כשהברירה הגלובלית דלוקה',
      () async {
        const key = 'o__9__משלי';
        await PerBookSettings.saveSettings(key, {
          'removePunctuation': false,
          'isTanach': true,
        });
        await runCleanup(defaultRemovePunctuation: true);
        // שווה לברירה האפקטיבית של תנ"ך (false) — השדה והדגל נמחקים יחד.
        expect(await PerBookSettings.loadSettings(key), isNull);
      },
    );

    test('קובץ tombstone שורד את הניקוי', () async {
      const key = 'o__5__דברים';
      await PerBookSettings.saveSettings(key, {
        PerBookSettings.resetMarker: true,
      });
      await runCleanup(defaultContinuous: true);
      expect(
        (await PerBookSettings.loadSettings(key))?[PerBookSettings.resetMarker],
        isTrue,
      );
    });

    test('קובץ legacy (שם לא-hash) אינו נוגע בניקוי', () async {
      // legacy הוא read-only artifact; הניקוי מתעלם ממנו כדי לא להתנגש עם
      // מיגרציה מקבילה. ה-override שלו מנוקה רק אחרי שהיגר לקובץ hash.
      final f = await writeLegacy('בראשית', {
        'continuousReadingMode': true,
        'activeCommentators': ['רש"י'],
      });
      await runCleanup(defaultContinuous: true);
      final json = readJson(f);
      expect(json, isNotNull);
      expect(json!['continuousReadingMode'], isTrue);
      expect(json['activeCommentators'], ['רש"י']);
    });
  });

  // חייב לרוץ אחרון: Settings.init הוא גלובלי, והקבוצות הקודמות מסתמכות
  // על מסלול ההעתקה-הגולמית (Settings לא מאותחל).
  group('מיגרציית legacy — נרמול מול ברירות המחדל', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('per_book_migrate');
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      await Settings.init(cacheProvider: MemorySettingsCache());
      await Settings.setValue('key-continuous-reading-mode', true);
    });

    tearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<File> writeLegacy(String name, Map<String, dynamic> json) async {
      final dir = Directory(p.join(tempDir.path, 'per_book_settings'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'settings_$name.json'));
      await file.writeAsString(jsonEncode(json));
      return file;
    }

    test('override ששווה לברירת המחדל מנורמל החוצה בהעתקה', () async {
      // הבאג שתוקן: copy גולמי קיבע override מפורש בקובץ ה-hash, והספר
      // לא ירש שינוי עתידי בברירת המחדל.
      final legacy = await writeLegacy('בראשית', {
        'continuousReadingMode': true,
        'activeCommentators': ['רש"י'],
      });
      final book = TextBook(title: 'בראשית', categoryId: 1);

      final loaded = await TextBookPerBookSettings.load(book);
      expect(loaded?.continuousReadingMode, isNull);
      expect(loaded?.activeCommentators, ['רש"י']);

      // בקובץ ה-hash עצמו השדה לא קיים; ה-legacy נשאר ללא שינוי.
      final hashJson = await PerBookSettings.loadSettings('o__1__בראשית');
      expect(hashJson!.containsKey('continuousReadingMode'), isFalse);
      final legacyJson =
          jsonDecode(legacy.readAsStringSync()) as Map<String, dynamic>;
      expect(legacyJson['continuousReadingMode'], isTrue);
    });

    test('כשכל השדות זהים לברירת המחדל נכתב tombstone', () async {
      // בלי tombstone, שינוי עתידי של ברירת המחדל היה מפעיל מיגרציה חוזרת
      // שמחיה את ה-override הישן מה-legacy.
      await writeLegacy('שמות', {'continuousReadingMode': true});
      final book = TextBook(title: 'שמות', categoryId: 2);

      final loaded = await TextBookPerBookSettings.load(book);
      expect(loaded?.continuousReadingMode, isNull);

      final hashJson = await PerBookSettings.loadSettings('o__2__שמות');
      expect(hashJson?[PerBookSettings.resetMarker], isTrue);
    });

    test('override ששונה מברירת המחדל כן מועתק', () async {
      await writeLegacy('ויקרא', {'continuousReadingMode': false});
      final book = TextBook(title: 'ויקרא', categoryId: 3);

      final loaded = await TextBookPerBookSettings.load(book);
      expect(loaded?.continuousReadingMode, isFalse);
    });
  });
}

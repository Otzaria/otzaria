import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

Link _link({
  required String path2,
  int index2 = 1,
  String connectionType = LinkTypes.commentary,
  int index1 = 1,
  int? categoryId = 7,
  int? start,
  int? end,
  int? index2End,
}) {
  return Link(
    heRef: path2,
    index1: index1,
    path2: path2,
    index2: index2,
    connectionType: connectionType,
    targetCategoryId: categoryId,
    start: start,
    end: end,
    index2End: index2End,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(TargetLineLinksService.resetInstanceForTesting);

  group('פיצול לקישורים ולמפרשים', () {
    test('קישור תלוי-טקסט נכנס למפרשים, הפניה נכנסת לקישורים', () async {
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(path2: 'מהרש"א', connectionType: LinkTypes.commentary),
          _link(path2: 'תרגום', connectionType: LinkTypes.targum),
          _link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat),
          _link(path2: 'רמב"ם', connectionType: LinkTypes.reference),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      final data = service.cached(_link(path2: 'רש"י'))!;
      expect(
        data.commentaries.map((l) => l.path2),
        containsAll(<String>['מהרש"א', 'תרגום']),
      );
      expect(
        data.references.map((l) => l.path2),
        containsAll(<String>['עין משפט', 'רמב"ם']),
      );
      expect(data.commentaries, hasLength(2));
      expect(data.references, hasLength(2));
    });

    test('סוג באותיות קטנות מזוהה כמפרש (נרמול)', () async {
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(path2: 'מהרש"א', connectionType: 'commentary'),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      expect(service.cached(_link(path2: 'רש"י'))!.commentaries, hasLength(1));
    });

    test('SOURCE הווירטואלי אינו מוצג באף אחת מהרשימות', () async {
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(path2: 'ברכות', connectionType: LinkTypes.source),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      final data = service.cached(_link(path2: 'רש"י'))!;
      expect(data.commentaries, isEmpty);
      expect(data.references, isEmpty);
    });

    test('קישור-טווח inline (start/end) אינו מוצג בקישורים', () async {
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(
            path2: 'הפניה inline',
            connectionType: LinkTypes.reference,
            start: 3,
            end: 9,
          ),
          _link(path2: 'הפניה רגילה', connectionType: LinkTypes.reference),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      final data = service.cached(_link(path2: 'רש"י'))!;
      expect(data.references.map((l) => l.path2), ['הפניה רגילה']);
    });

    test('אותו יעד באותה שורה מוצג פעם אחת', () async {
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(path2: 'מהרש"א', index2: 4),
          _link(path2: 'מהרש"א', index2: 4),
          _link(path2: 'מהרש"א', index2: 9),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      expect(service.cached(_link(path2: 'רש"י'))!.commentaries, hasLength(2));
    });

    test('הפניה inline אינה בולעת הפניה רגילה לאותו יעד', () async {
      // הדדופ חייב לרוץ אחרי הסיווג: קישור שנזרק תפס את המשבצת ומחק את
      // ההפניה הלגיטימית, והפריט "קישורים" יצא אפור.
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(
            path2: 'רמב"ם',
            index2: 12,
            connectionType: LinkTypes.reference,
            start: 3,
            end: 9,
          ),
          _link(
            path2: 'רמב"ם',
            index2: 12,
            connectionType: LinkTypes.reference,
          ),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      expect(service.cached(_link(path2: 'רש"י'))!.references, hasLength(1));
    });

    test('מפרש והפניה לאותו יעד מופיעים כל אחד ברשימה שלו', () async {
      // דדופ משותף לשתי הרשימות היה מותיר רק את הראשון בסדר השאילתה.
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(
            path2: 'יעד',
            index2: 4,
            connectionType: LinkTypes.commentary,
          ),
          _link(
            path2: 'יעד',
            index2: 4,
            connectionType: LinkTypes.mesoratHashas,
          ),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      final data = service.cached(_link(path2: 'רש"י'))!;
      expect(data.commentaries, hasLength(1));
      expect(data.references, hasLength(1));
    });

    test('קישור בלי יעד תקין מסונן', () async {
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(path2: '', index2: 3),
          _link(path2: 'תקין', index2: 0),
          _link(path2: 'תקין', index2: 3),
        ],
      );

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      expect(service.cached(_link(path2: 'רש"י'))!.commentaries, hasLength(1));
    });
  });

  group('מטמון וטעינה', () {
    test('cached מחזיר null עד שהטעינה מסתיימת', () async {
      // שער מפורש ולא השהיית שעון-קיר, שלא ייווצר טסט תלוי-עומס.
      final gate = Completer<void>();
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          await gate.future;
          return [_link(path2: 'מהרש"א')];
        },
      );
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();
      expect(service.cached(link), isNull);

      gate.complete();
      await pumpEventQueue();
      expect(service.cached(link), isNotNull);
    });

    test('clearCache בזמן טעינה — התוצאה אינה חוזרת למטמון', () async {
      final gate = Completer<void>();
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          await gate.future;
          return [_link(path2: 'מהרש"א')];
        },
      );
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();
      service.clearCache();

      gate.complete();
      await pumpEventQueue();
      expect(service.cached(link), isNull);
      expect(service.cacheSize, 0);
    });

    test(
      'כשל של טעינה ישנה אינו מוחק placeholder של טעינה שאחרי clearCache',
      () async {
        // החלפת ספרייה בזמן טעינה: בלי מזהה-דור, ה-catch של הטעינה הישנה היה
        // מוחק את ה-placeholder של החדשה, והתת-תפריט נשאר "טוען…" לצמיתות.
        final gates = <Completer<void>>[];
        final service = TargetLineLinksService(
          loader: (_, _, _) async {
            final gate = Completer<void>();
            gates.add(gate);
            await gate.future;
            if (gates.length == 1) throw StateError('DB נעול');
            return [_link(path2: 'מהרש"א')];
          },
        );
        final link = _link(path2: 'רש"י');

        service.prefetch(link);
        await pumpEventQueue();
        service.clearCache();
        service.prefetch(link);
        await pumpEventQueue();
        expect(gates, hasLength(2));

        gates[0].complete(); // הישנה נכשלת
        await pumpEventQueue();
        gates[1].complete(); // החדשה מצליחה
        await pumpEventQueue();

        expect(service.cached(link)!.commentaries, hasLength(1));
      },
    );

    test('תוצאה מלפני clearCache אינה נכתבת למטמון', () async {
      final gate = Completer<void>();
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          await gate.future;
          return [_link(path2: 'מהמסד הישן')];
        },
      );
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();
      service.clearCache();

      gate.complete();
      await pumpEventQueue();

      expect(service.cached(link), isNull);
      expect(service.cacheSize, 0);
    });

    test('clearCache פולט לזרם ומבטל ריחוף ממתין', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );
      final emissions = <void>[];
      final sub = service.refreshStream.listen(emissions.add);

      service.prefetchOnHover(_link(path2: 'רש"י'));
      service.clearCache();
      await Future<void>.delayed(
        TargetLineLinksService.hoverPrefetchDelay * 2,
      );

      expect(emissions, hasLength(1));
      expect(loads, 0, reason: 'הריחוף הממתין בוטל');
      await sub.cancel();
    });

    test('טעינה שמסתיימת אחרי איפוס המופע אינה זורקת', () async {
      final gate = Completer<void>();
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async {
          await gate.future;
          return const [];
        },
      );
      final service = TargetLineLinksService.instance;

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();
      // סוגר את ה-StreamController שהטעינה התלויה עומדת לפלוט אליו.
      TargetLineLinksService.resetInstanceForTesting();

      gate.complete();
      await expectLater(pumpEventQueue(), completes);
    });

    test('prefetch חוזר על אותו קטע אינו טוען פעמיים', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );
      final link = _link(path2: 'רש"י', index2: 5);

      service.prefetch(link);
      service.prefetch(link);
      await pumpEventQueue();
      service.prefetch(link);
      await pumpEventQueue();

      expect(loads, 1);
    });

    test('ספר אישי וספר רשמי באותה כותרת אינם חולקים ערך במטמון', () async {
      // מזהי הקטגוריה של user_books.db הם מרחב נפרד, ולכן שתי הכותרות יכולות
      // להתנגש (כולל null == null) ולהחזיר זו את הקישורים של זו.
      final service = TargetLineLinksService(
        loader: (book, _, _) async => [
          _link(path2: book.isUserBook ? 'יעד אישי' : 'יעד רשמי'),
        ],
      );
      final official = Link(
        heRef: 'x',
        index1: 1,
        path2: 'רש"י',
        index2: 5,
        connectionType: LinkTypes.commentary,
      );
      final personal = Link(
        heRef: 'x',
        index1: 1,
        path2: 'רש"י',
        index2: 5,
        connectionType: LinkTypes.commentary,
        targetIsUserBook: true,
      );

      service.prefetch(official);
      service.prefetch(personal);
      await pumpEventQueue();

      expect(service.cached(official)!.commentaries.single.path2, 'יעד רשמי');
      expect(service.cached(personal)!.commentaries.single.path2, 'יעד אישי');
    });

    test('שורות שונות באותו ספר נטענות בנפרד', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );

      service.prefetch(_link(path2: 'רש"י', index2: 5));
      service.prefetch(_link(path2: 'רש"י', index2: 6));
      await pumpEventQueue();

      expect(loads, 2);
    });

    test('כישלון זמני אינו מקובע — ניסיון חוזר טוען שוב', () async {
      // DB נעול בסנכרון רקע: קיבוע רשימה ריקה היה מותיר את הפריט אפור עד
      // הפעלה מחדש, למרות שיש מפרשים.
      var attempts = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          attempts++;
          if (attempts == 1) throw StateError('DB נעול');
          return [_link(path2: 'מהרש"א')];
        },
      );
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();
      expect(service.cached(link), isNull, reason: 'הכישלון לא נשמר במטמון');

      service.prefetch(link);
      await pumpEventQueue();
      expect(service.cached(link)!.commentaries, hasLength(1));
    });

    test('כישלון אינו פולט לזרם — אחרת נוצרת לולאת שאילתות', () async {
      // הזרם בונה מחדש את תת-התפריט, שקורא ל-prefetch. פליטה בכשל הייתה
      // סוגרת מעגל: כשל → פליטה → בנייה → prefetch → כשל, בלי הפוגה.
      final service = TargetLineLinksService(
        loader: (_, _, _) async => throw StateError('DB לא זמין'),
      );
      final emissions = <void>[];
      final sub = service.refreshStream.listen(emissions.add);

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      expect(emissions, isEmpty);
      await sub.cancel();
    });

    test('clearCache מנקה ומאפשר טעינה מחדש', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();
      service.clearCache();

      expect(service.cached(link), isNull);
      expect(service.cacheSize, 0);

      service.prefetch(link);
      await pumpEventQueue();
      expect(loads, 2);
    });

    test('פינוי אינו נוגע בקטע שנמצא בטעינה', () async {
      final gate = Completer<void>();
      final service = TargetLineLinksService(
        loader: (book, _, _) async {
          if (book.title == 'איטי') await gate.future;
          return const [];
        },
      );
      final slow = _link(path2: 'איטי');

      service.prefetch(slow);
      for (var i = 1; i <= 300; i++) {
        service.prefetch(_link(path2: 'ספר', index2: i));
      }
      await pumpEventQueue();

      gate.complete();
      await pumpEventQueue();
      expect(
        service.cached(slow),
        isNotNull,
        reason: 'פינוי מפתח בטעינה היה משאיר תת-תפריט פתוח תקוע ב"טוען…"',
      );
    });

    test('המטמון מפנה לפי שימוש אחרון ולא לפי סדר הכנסה', () async {
      final service = TargetLineLinksService(loader: (_, _, _) async => []);

      for (var i = 1; i <= 256; i++) {
        service.prefetch(_link(path2: 'ספר', index2: i));
      }
      await pumpEventQueue();

      // נגיעה בוותיק ביותר מחדשת אותו; הבא בתור הוא שאמור לפנות.
      final oldest = _link(path2: 'ספר', index2: 1);
      expect(service.cached(oldest), isNotNull);

      service.prefetch(_link(path2: 'ספר', index2: 999));
      await pumpEventQueue();

      expect(service.cached(oldest), isNotNull);
      expect(service.cached(_link(path2: 'ספר', index2: 2)), isNull);
    });

    test('טעינה פולטת לזרם פעם אחת בלבד', () async {
      // פליטה שנייה הייתה מסדרת את הרשימה מחדש מול עיני המשתמש.
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [_link(path2: 'מהרש"א')],
      );
      final emissions = <void>[];
      final sub = service.refreshStream.listen(emissions.add);

      service.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      expect(emissions, hasLength(1));
      await sub.cancel();
    });

    test('קישור בלי יעד תקין אינו מפעיל טעינה כלל', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );

      service.prefetch(_link(path2: '', index2: 1));
      service.prefetch(_link(path2: 'רש"י', index2: 0));
      await pumpEventQueue();

      expect(loads, 0);
      expect(service.cacheSize, 0);
    });

    test('המטמון חסום ומפנה את הוותיק ביותר', () async {
      final service = TargetLineLinksService(loader: (_, _, _) async => []);

      for (var i = 1; i <= 300; i++) {
        service.prefetch(_link(path2: 'ספר', index2: i));
      }
      await pumpEventQueue();

      expect(service.cacheSize, lessThanOrEqualTo(256));
      expect(service.cached(_link(path2: 'ספר', index2: 1)), isNull);
      expect(service.cached(_link(path2: 'ספר', index2: 300)), isNotNull);
    });
  });

  group('כשל טעינה', () {
    Link failing() => _link(path2: 'רש"י');

    TargetLineLinksService failingService(int failuresBeforeSuccess) {
      var attempts = 0;
      return TargetLineLinksService(
        loader: (_, _, _) async {
          attempts++;
          if (attempts <= failuresBeforeSuccess) {
            throw StateError('ספר היעד חסר');
          }
          return [_link(path2: 'מהרש"א')];
        },
      );
    }

    test('קטע שנכשל מציג "שגיאה בטעינה" ולא "טוען…"', () async {
      final service = failingService(99);
      final entry = service.buildCommentariesEntry(
        link: failing(),
        onNavigate: (_) {},
      );

      entry.childrenBuilder!();
      await pumpEventQueue();

      expect(entry.childrenBuilder!().single.label, 'שגיאה בטעינה');
    });

    test('בנייה חוזרת אחרי כשל אינה יורה שאילתה נוספת', () async {
      // בלי הסימון, כל פליטה לזרם הייתה מפעילה שאילתה כושלת נוספת.
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          throw StateError('ספר היעד חסר');
        },
      );
      final entry = service.buildCommentariesEntry(
        link: failing(),
        onNavigate: (_) {},
      );

      entry.childrenBuilder!();
      await pumpEventQueue();
      for (var i = 0; i < 5; i++) {
        entry.childrenBuilder!();
        await pumpEventQueue();
      }

      expect(loads, 1);
    });

    test('ריחוף חדש אחרי כשל מנסה שוב ומצליח', () async {
      final service = failingService(1);
      final link = failing();

      service.prefetch(link);
      await pumpEventQueue();
      expect(service.cached(link), isNull);

      service.prefetchOnHover(link);
      await Future<void>.delayed(
        TargetLineLinksService.hoverPrefetchDelay * 2,
      );
      await pumpEventQueue();

      expect(service.cached(link)!.commentaries, hasLength(1));
    });

    test('לחיצה ימנית אחרי כשל מנסה שוב', () async {
      final service = failingService(1);
      final link = failing();

      service.prefetch(link);
      await pumpEventQueue();
      service.prefetch(link);
      await pumpEventQueue();

      expect(service.cached(link)!.commentaries, hasLength(1));
    });

    test('הצלחה אחרי כשל מנקה את סימון הכשל', () async {
      final service = failingService(1);
      final link = failing();
      final entry = service.buildCommentariesEntry(
        link: link,
        onNavigate: (_) {},
      );

      entry.childrenBuilder!();
      await pumpEventQueue();
      service.prefetch(link);
      await pumpEventQueue();

      expect(entry.childrenBuilder!().single.label, contains('מהרש"א'));
    });

    test('clearCache מנקה סימוני כשל', () async {
      final service = failingService(1);
      final link = failing();
      final entry = service.buildCommentariesEntry(
        link: link,
        onNavigate: (_) {},
      );

      entry.childrenBuilder!();
      await pumpEventQueue();
      service.clearCache();

      // אחרי הניקוי הבנייה חוזרת לנסות, והפעם ה-loader מצליח.
      entry.childrenBuilder!();
      await pumpEventQueue();
      expect(service.cached(link)!.commentaries, hasLength(1));
    });

    test('כשל בקטע אחד אינו משפיע על קטע אחר', () async {
      final service = TargetLineLinksService(
        loader: (book, _, _) async {
          if (book.title == 'שבור') throw StateError('חסר');
          return [_link(path2: 'מהרש"א')];
        },
      );
      final broken = _link(path2: 'שבור');
      final healthy = _link(path2: 'תקין');

      service.prefetch(broken);
      service.prefetch(healthy);
      await pumpEventQueue();

      expect(service.cached(broken), isNull);
      expect(service.cached(healthy)!.commentaries, hasLength(1));
    });
  });

  group('טעינה מקדימה בריחוף', () {
    test('סמן שנעצר על פריט טוען אותו', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );

      service.prefetchOnHover(_link(path2: 'רש"י'));
      expect(loads, 0, reason: 'הטעינה נדחית עד שהסמן נעצר');

      await Future<void>.delayed(
        TargetLineLinksService.hoverPrefetchDelay * 2,
      );
      expect(loads, 1);
    });

    test('סמן שחולף מעל רשימה טוען רק את הפריט שעליו נעצר', () async {
      final loaded = <String>[];
      final service = TargetLineLinksService(
        loader: (book, _, _) async {
          loaded.add(book.title);
          return const [];
        },
      );

      for (var i = 1; i <= 20; i++) {
        service.prefetchOnHover(_link(path2: 'מפרש $i'));
      }
      await Future<void>.delayed(
        TargetLineLinksService.hoverPrefetchDelay * 2,
      );

      expect(loaded, ['מפרש 20']);
    });

    test('ריחוף על קטע שכבר במטמון אינו קובע טיימר מיותר', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();
      service.prefetchOnHover(link);
      await Future<void>.delayed(
        TargetLineLinksService.hoverPrefetchDelay * 2,
      );

      expect(loads, 1);
    });

    test('ריחוף אחרי לחיצה ימנית אינו טוען שוב', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );
      final link = _link(path2: 'רש"י');

      service.prefetchOnHover(link);
      service.prefetch(link);
      await Future<void>.delayed(
        TargetLineLinksService.hoverPrefetchDelay * 2,
      );

      expect(loads, 1);
    });
  });

  group('טווח הטעינה', () {
    test('קישור לשורה בודדת טוען את אותה שורה בלבד', () async {
      int? start;
      int? end;
      final service = TargetLineLinksService(
        loader: (_, s, e) async {
          start = s;
          end = e;
          return const [];
        },
      );

      service.prefetch(_link(path2: 'רש"י', index2: 12));
      await pumpEventQueue();

      expect(start, 11);
      expect(end, 11);
    });

    test('קישור-טווח טוען את הטווח, חסום בתקרה', () async {
      int? start;
      int? end;
      final service = TargetLineLinksService(
        loader: (_, s, e) async {
          start = s;
          end = e;
          return const [];
        },
      );

      service.prefetch(_link(path2: 'רש"י', index2: 5, index2End: 100));
      await pumpEventQueue();

      expect(start, 4);
      expect(end, 14);
    });

    test('index2End קטן מ-index2 נטען כשורה בודדת', () async {
      int? start;
      int? end;
      final service = TargetLineLinksService(
        loader: (_, s, e) async {
          start = s;
          end = e;
          return const [];
        },
      );

      service.prefetch(_link(path2: 'רש"י', index2: 10, index2End: 3));
      await pumpEventQueue();

      expect(start, 9);
      expect(end, 9);
    });

    test('טווח קצר מהתקרה אינו נחתך', () async {
      int? start;
      int? end;
      final service = TargetLineLinksService(
        loader: (_, s, e) async {
          start = s;
          end = e;
          return const [];
        },
      );

      service.prefetch(_link(path2: 'רש"י', index2: 5, index2End: 8));
      await pumpEventQueue();

      expect(start, 4);
      expect(end, 7);
    });

    test('השורה הראשונה בספר נטענת מאינדקס 0', () async {
      int? start;
      final service = TargetLineLinksService(
        loader: (_, s, _) async {
          start = s;
          return const [];
        },
      );

      service.prefetch(_link(path2: 'רש"י', index2: 1));
      await pumpEventQueue();

      expect(start, 0);
    });

    test('ספר היעד נגזר מהקישור על כל שדותיו', () async {
      TextBook? loadedBook;
      final service = TargetLineLinksService(
        loader: (book, _, _) async {
          loadedBook = book;
          return const [];
        },
      );

      service.prefetch(
        Link(
          heRef: 'x',
          index1: 1,
          path2: 'רש"י על ברכות',
          index2: 5,
          connectionType: LinkTypes.commentary,
          targetCategoryId: 42,
          targetFileType: 'docx',
          targetIsUserBook: true,
        ),
      );
      await pumpEventQueue();

      expect(loadedBook!.title, 'רש"י על ברכות');
      expect(loadedBook!.categoryId, 42);
      expect(loadedBook!.fileType, 'docx');
      expect(loadedBook!.isUserBook, isTrue);
    });
  });

  group('פריטי התפריט', () {
    AppContextMenuEntry commentariesEntry(
      TargetLineLinksService service,
      Link link,
    ) => service.buildCommentariesEntry(link: link, onNavigate: (_) {});

    AppContextMenuEntry linksEntry(
      TargetLineLinksService service,
      Link link,
    ) => service.buildLinksEntry(link: link, onNavigate: (_) {});

    test('לפני טעינה הפריט פעיל ומציג "טוען…"', () {
      final service = TargetLineLinksService(loader: (_, _, _) async => []);
      final entry = commentariesEntry(service, _link(path2: 'רש"י'));

      expect(entry.label, 'מפרשים');
      expect(entry.enabled, isTrue);
      expect(entry.childrenBuilder!().single.label, 'טוען…');
    });

    test('אחרי טעינה ריקה הפריט אפור', () async {
      final service = TargetLineLinksService(loader: (_, _, _) async => []);
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();

      expect(commentariesEntry(service, link).enabled, isFalse);
      expect(linksEntry(service, link).enabled, isFalse);
    });

    test('פריט אפור רק בצד שריק', () async {
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(path2: 'מהרש"א', connectionType: LinkTypes.commentary),
        ],
      );
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();

      expect(commentariesEntry(service, link).enabled, isTrue);
      expect(linksEntry(service, link).enabled, isFalse);
    });

    test('קישור בלי יעד תקין אפור ואינו נתקע ב"טוען…"', () {
      final service = TargetLineLinksService(loader: (_, _, _) async => []);

      for (final broken in [
        _link(path2: '', index2: 3),
        _link(path2: 'רש"י', index2: 0),
      ]) {
        final entry = commentariesEntry(service, broken);
        expect(entry.enabled, isFalse);
        expect(entry.childrenBuilder!().single.label, isNot('טוען…'));
      }
    });

    test('רשימה ריקה מציגה הודעה מושבתת ולא פריט לחיץ', () async {
      final service = TargetLineLinksService(loader: (_, _, _) async => []);
      final link = _link(path2: 'רש"י');

      service.prefetch(link);
      await pumpEventQueue();

      final child = commentariesEntry(service, link).childrenBuilder!().single;
      expect(child.label, 'אין מפרשים על קטע זה');
      expect(child.enabled, isFalse);
    });

    test('לחיצה על פריט מנווטת אל אותו קישור', () async {
      final target = _link(path2: 'מהרש"א', index2: 8);
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [target],
      );
      final link = _link(path2: 'רש"י');
      Link? navigated;

      service.prefetch(link);
      await pumpEventQueue();

      final entry = service.buildCommentariesEntry(
        link: link,
        onNavigate: (l) => navigated = l,
      );
      entry.childrenBuilder!().single.onTap!();

      expect(navigated, same(target));
    });

    test('בניית הפריט לבדה מפעילה טעינה (בלי ריחוף מקדים)', () async {
      var loads = 0;
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );

      commentariesEntry(service, _link(path2: 'רש"י')).childrenBuilder!();
      await pumpEventQueue();

      expect(loads, 1);
    });

    test('זרם הרענון של הפריט פולט כשהטעינה מסתיימת', () async {
      // ה-getter של broadcast stream מחזיר עטיפה חדשה בכל קריאה, ולכן בודקים
      // שהזרם *פועל* ולא שהוא אותו מופע.
      final gate = Completer<void>();
      final service = TargetLineLinksService(
        loader: (_, _, _) async {
          await gate.future;
          return [_link(path2: 'מהרש"א')];
        },
      );
      final entry = commentariesEntry(service, _link(path2: 'רש"י'));
      final emissions = <void>[];
      final sub = entry.childrenRefreshStream!.listen(emissions.add);

      entry.childrenBuilder!();
      await pumpEventQueue();
      expect(emissions, isEmpty);

      gate.complete();
      await pumpEventQueue();
      expect(emissions, hasLength(1));
      expect(entry.childrenBuilder!().single.label, contains('מהרש"א'));
      await sub.cancel();
    });

    test('לשני הפריטים אייקונים נבדלים ותוויות נכונות', () {
      final service = TargetLineLinksService(loader: (_, _, _) async => []);
      final link = _link(path2: 'רש"י');

      final commentaries = commentariesEntry(service, link);
      final links = linksEntry(service, link);

      expect(commentaries.label, 'מפרשים');
      expect(links.label, 'קישורים');
      expect(commentaries.icon, isNot(links.icon));
    });
  });

  group('מפרידי דורות', () {
    setUp(CommentaryService.clearEraCache);
    tearDown(CommentaryService.clearEraCache);

    Future<List<AppContextMenuEntry>> childrenFor(List<Link> loaded) async {
      final service = TargetLineLinksService(loader: (_, _, _) async => loaded);
      final link = _link(path2: 'רש"י');
      service.prefetch(link);
      await pumpEventQueue();
      return service
          .buildCommentariesEntry(link: link, onNavigate: (_) {})
          .childrenBuilder!();
    }

    test('מעבר בין דורות מוסיף פס מבדיל', () async {
      CommentaryService.seedEraCache({
        'רשב"ם': CommentaryEra.rishonim,
        'מהרש"א': CommentaryEra.acharonim,
      });

      final children = await childrenFor([
        _link(path2: 'רשב"ם'),
        _link(path2: 'מהרש"א'),
      ]);

      expect(children.where((e) => e.isDivider), hasLength(1));
    });

    test('אותו דור אינו מקבל פס מבדיל', () async {
      CommentaryService.seedEraCache({
        'רשב"ם': CommentaryEra.rishonim,
        'רמב"ן': CommentaryEra.rishonim,
      });

      final children = await childrenFor([
        _link(path2: 'רשב"ם'),
        _link(path2: 'רמב"ן'),
      ]);

      expect(children.where((e) => e.isDivider), isEmpty);
    });

    test('"הערות על XX" אינו שובר את קבוצת הדור של XX', () async {
      // המיון מעגן "הערות על רש״י" לדור של רש״י. אם המפריד נגזר מהכותרת
      // עצמה (=שאר מפרשים) נוצרים שני מפרידים מזויפים בתוך אותו דור.
      CommentaryService.seedEraCache({
        'רש"י': CommentaryEra.rishonim,
        'רשב"ם': CommentaryEra.rishonim,
      });

      final children = await childrenFor([
        _link(path2: 'רש"י'),
        _link(path2: 'הערות על רש"י'),
        _link(path2: 'רשב"ם'),
      ]);

      expect(children.where((e) => e.isDivider), isEmpty);
    });

    test('רשימת הקישורים אינה מקבלת מפרידי דורות', () async {
      CommentaryService.seedEraCache({
        'עין משפט': CommentaryEra.rishonim,
        'מסורת הש"ס': CommentaryEra.acharonim,
      });
      final service = TargetLineLinksService(
        loader: (_, _, _) async => [
          _link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat),
          _link(path2: 'מסורת הש"ס', connectionType: LinkTypes.mesoratHashas),
        ],
      );
      final link = _link(path2: 'רש"י');
      service.prefetch(link);
      await pumpEventQueue();

      final children = service
          .buildLinksEntry(link: link, onNavigate: (_) {})
          .childrenBuilder!();

      expect(children.where((e) => e.isDivider), isEmpty);
      expect(children, hasLength(2));
    });

    test('הרשימה ממוינת לפי סדר הדורות ולא לפי סדר השאילתה', () async {
      CommentaryService.seedEraCache({
        'מהרש"א': CommentaryEra.acharonim,
        'רשב"ם': CommentaryEra.rishonim,
      });

      final children = await childrenFor([
        _link(path2: 'מהרש"א'),
        _link(path2: 'רשב"ם'),
      ]);

      final labels = children
          .where((e) => !e.isDivider)
          .map((e) => e.label)
          .toList();
      expect(labels.first, contains('רשב"ם'));
      expect(labels.last, contains('מהרש"א'));
    });

    test('sortingEraForLink מעגן "הערות על XX" לדור של XX', () {
      CommentaryService.seedEraCache({'רש"י': CommentaryEra.rishonim});
      final notes = _link(path2: 'הערות על רש"י');

      expect(
        CommentaryService.sortingEraForLink(notes, {'רש"י', 'הערות על רש"י'}),
        CommentaryEra.rishonim,
      );
    });

    test('sortingEraForLink נופל ל"שאר מפרשים" כשהבסיס אינו ברשימה', () {
      CommentaryService.seedEraCache({'רש"י': CommentaryEra.rishonim});
      final notes = _link(path2: 'הערות על רש"י');

      expect(
        CommentaryService.sortingEraForLink(notes, {'הערות על רש"י'}),
        CommentaryEra.other,
      );
    });
  });

  group('singleton', () {
    test('resetInstanceForTesting מחליף את המימוש', () async {
      var loads = 0;
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async {
          loads++;
          return const [];
        },
      );

      TargetLineLinksService.instance.prefetch(_link(path2: 'רש"י'));
      await pumpEventQueue();

      expect(loads, 1);
    });

    test('איפוס מנקה את המטמון של המופע הקודם', () async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [],
      );
      final link = _link(path2: 'רש"י');
      TargetLineLinksService.instance.prefetch(link);
      await pumpEventQueue();
      expect(TargetLineLinksService.instance.cached(link), isNotNull);

      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [],
      );
      expect(TargetLineLinksService.instance.cached(link), isNull);
    });
  });
}

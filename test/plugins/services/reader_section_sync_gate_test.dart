import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/reader_section_content_tracker.dart';
import 'package:otzaria/plugins/services/reader_section_sync_gate.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  late ReaderSectionSyncGate gate;
  final signature = const RenderSettings(
    fontSize: 18,
  ).sectionContentRenderingSignature;

  setUp(() => gate = ReaderSectionSyncGate.forTesting());

  bool sync({
    String bookId = 'book',
    int sectionIndex = 4,
    String rawSourceHtml = '<b>בראשית</b> ברא',
    String processedHtml = '<b>בראשית</b> ברא',
    Object? renderingSignature,
    int highlightsRevision = 0,
  }) {
    return gate.claimSync(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawSourceHtml: rawSourceHtml,
      processedHtml: processedHtml,
      renderingSignature: renderingSignature ?? signature,
      highlightsRevision: highlightsRevision,
    );
  }

  group('חסימת עבודה חוזרת', () {
    test('הקריאה הראשונה מסנכרנת, הבאות אחריה נחסמות', () {
      expect(sync(), isTrue);
      expect(sync(), isFalse);
      expect(sync(), isFalse);
      expect(sync(), isFalse);
    });

    test('מחרוזות שוות-ערך אך לא זהות-מופע נחסמות גם הן', () {
      expect(sync(rawSourceHtml: 'אותו טקסט'), isTrue);
      // מופע חדש עם אותו תוכן — חייב להיחסם, אחרת כל פריים ישלם מחדש.
      expect(
        sync(rawSourceHtml: String.fromCharCodes('אותו טקסט'.codeUnits)),
        isFalse,
      );
    });

    test('קטעים שונים נספרים בנפרד', () {
      expect(sync(sectionIndex: 1), isTrue);
      expect(sync(sectionIndex: 2), isTrue);
      expect(sync(sectionIndex: 1), isFalse);
      expect(sync(sectionIndex: 2), isFalse);
    });

    test('ספרים שונים באותו אינדקס קטע נספרים בנפרד', () {
      expect(sync(bookId: 'בראשית'), isTrue);
      expect(sync(bookId: 'שמות'), isTrue);
      expect(sync(bookId: 'בראשית'), isFalse);
      expect(sync(bookId: 'שמות'), isFalse);
    });
  });

  group('מה מחייב סנכרון מחדש', () {
    test('שינוי בטקסט המקור', () {
      expect(sync(), isTrue);
      expect(sync(rawSourceHtml: 'טקסט אחר'), isTrue);
      expect(sync(rawSourceHtml: 'טקסט אחר'), isFalse);
    });

    test('שינוי בתוצר המעובד בלבד — למשל הסרת ניקוד', () {
      expect(sync(processedHtml: 'בְּרֵאשִׁית'), isTrue);
      expect(sync(processedHtml: 'בראשית'), isTrue);
      expect(sync(processedHtml: 'בראשית'), isFalse);
    });

    test('שינוי חתימת רינדור שאינו נוגע בטקסט — למשל גודל גופן', () {
      expect(sync(), isTrue);
      expect(sync(), isFalse);
      expect(
        sync(
          renderingSignature: const RenderSettings(
            fontSize: 30,
          ).sectionContentRenderingSignature,
        ),
        isTrue,
      );
    });

    test('חתימה שוות-ערך מאובייקט אחר אינה מחייבת סנכרון', () {
      expect(sync(), isTrue);
      expect(
        sync(
          renderingSignature: const RenderSettings(
            fontSize: 18,
          ).sectionContentRenderingSignature,
        ),
        isFalse,
      );
    });

    test('שינוי ב-revision של ההיילייטים — highlight חדש חייב עיגון', () {
      expect(sync(), isTrue);
      expect(sync(), isFalse);
      expect(sync(highlightsRevision: 1), isTrue);
      expect(sync(highlightsRevision: 1), isFalse);
    });

    test('חזרה לערך קודם עדיין מחייבת סנכרון', () {
      expect(sync(rawSourceHtml: 'א'), isTrue);
      expect(sync(rawSourceHtml: 'ב'), isTrue);
      expect(sync(rawSourceHtml: 'א'), isTrue);
    });
  });

  group('ניהול זיכרון ומחזור חיים', () {
    test('הזיכרון חסום ב-maxEntries', () {
      gate = ReaderSectionSyncGate.forTesting(maxEntries: 3);
      for (var i = 0; i < 10; i++) {
        sync(sectionIndex: i);
      }
      expect(gate.trackedSections, 3);
    });

    test('קטע שפונה מהזיכרון מסתנכרן מחדש, בלי לשבור נכונות', () {
      gate = ReaderSectionSyncGate.forTesting(maxEntries: 2);
      expect(sync(sectionIndex: 1), isTrue);
      expect(sync(sectionIndex: 2), isTrue);
      expect(sync(sectionIndex: 3), isTrue);
      // קטע 1 פונה — הקריאה הבאה עליו משלמת שוב.
      expect(sync(sectionIndex: 1), isTrue);
    });

    test('התקרה קטנה מזו של הטראקר, כדי שקו-הבסיס לא ייעלם לפני הסימון', () {
      expect(
        ReaderSectionSyncGate.defaultMaxEntries,
        lessThan(ReaderSectionContentTracker.instance.maxSnapshots),
      );
    });

    test('forget מבטל סימון של קטע בודד בלבד', () {
      expect(sync(sectionIndex: 1), isTrue);
      expect(sync(sectionIndex: 2), isTrue);

      gate.forget(bookId: 'book', sectionIndex: 1);

      expect(sync(sectionIndex: 1), isTrue);
      expect(sync(sectionIndex: 2), isFalse);
    });

    test('forgetBook מאפס רק את הספר שצוין', () {
      expect(sync(bookId: 'בראשית'), isTrue);
      expect(sync(bookId: 'שמות'), isTrue);

      gate.forgetBook('בראשית');

      expect(sync(bookId: 'בראשית'), isTrue);
      expect(sync(bookId: 'שמות'), isFalse);
    });

    test('clear מאפס הכל', () {
      expect(sync(sectionIndex: 1), isTrue);
      expect(sync(sectionIndex: 2), isTrue);

      gate.clear();

      expect(gate.trackedSections, 0);
      expect(sync(sectionIndex: 1), isTrue);
      expect(sync(sectionIndex: 2), isTrue);
    });
  });
}

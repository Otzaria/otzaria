// בדיקות רגרסיה: אסור לממש גלילה עצמאית ב-PdfBookScreen.
//
// רקע: פעמים רבות מישהו ניסה "לתקן" משהו בגלילה של ה-PDF Viewer ע"י מימוש
// גלילה עצמאית - תפיסת PointerScrollEvent / PointerPanZoom* וביצוע
// translate ידני על ה-matrix של ה-controller.
// כל מימוש כזה גרם לרגרסיות (קפיצות, פספוס דפים, שבירת ה-anchor של
// מצב הספר וכו'), ולבסוף הוסר בקומיט
// 3f6600693335d04d38754abf7ab8cbfb21d1c032 ("PDF: תיקון גלילה ועדכון לגלילה רגילה")
// שהחזיר את הגלילה לטיפול של חבילת pdfrx (scrollByMouseWheel + handlePointerSignalEvent).
//
// הבדיקות כאן סורקות את קוד המקור של pdf_book_screen.dart ומכשילות את הבילד
// אם מישהו מנסה להחזיר את הגלילה העצמאית. זהו "guard test" ארכיטקטוני.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // נתיב יחסי לשורש הפרויקט (CWD בעת הרצת הטסטים).
  final sourceFile = File('lib/pdf_book/view/pdf_book_screen.dart');

  late final String source;

  setUpAll(() async {
    expect(
      sourceFile.existsSync(),
      isTrue,
      reason: 'הקובץ lib/pdf_book/view/pdf_book_screen.dart חייב להיות קיים',
    );
    source = await sourceFile.readAsString();
  });

  group('PdfBookScreen — אסור לממש גלילה עצמאית', () {
    test('scrollByMouseWheel מועבר לחבילת pdfrx ולא מנוטרל (0.0)', () {
      // ערך 0.0 (או 0) משמעו ניטרול הגלילה הפנימית של pdfrx —
      // זה הסימן הראשון שמישהו עומד לממש גלילה ידנית.
      final disabledPatterns = [
        RegExp(r'scrollByMouseWheel\s*:\s*0\.0\b'),
        RegExp(r'scrollByMouseWheel\s*:\s*0\b(?!\.)'),
      ];
      for (final pattern in disabledPatterns) {
        expect(
          pattern.hasMatch(source),
          isFalse,
          reason:
              'אסור לאפס את scrollByMouseWheel — זה משבית את הגלילה של pdfrx '
              'ובהכרח מצריך מימוש גלילה עצמאית. השאר ערך חיובי (לדוגמה 0.2).',
        );
      }

      // ודא שהפרמטר אכן מוגדר עם ערך לא־אפס.
      expect(
        RegExp(r'scrollByMouseWheel\s*:\s*0?\.[1-9]').hasMatch(source) ||
            RegExp(r'scrollByMouseWheel\s*:\s*[1-9]').hasMatch(source),
        isTrue,
        reason:
            'scrollByMouseWheel חייב להיות מוגדר עם ערך חיובי כדי שחבילת pdfrx '
            'תטפל בגלילת הגלגלת.',
      );
    });

    test('אין handlers עצמאיים של PointerPanZoom (טראקפד דו-אצבעי)', () {
      // ה-handlers הללו שימשו למימוש גלילה ידנית של טראקפד — pdfrx מטפל בזה לבד.
      const forbidden = [
        'onPointerPanZoomStart',
        'onPointerPanZoomUpdate',
        'onPointerPanZoomEnd',
      ];
      for (final handler in forbidden) {
        expect(
          source.contains(handler),
          isFalse,
          reason:
              'אסור להשתמש ב-$handler ב-PdfBookScreen. '
              'גלילת טראקפד צריכה להיות מטופלת ע"י pdfrx (handlePointerSignalEvent) '
              'ולא ע"י translate ידני על ה-matrix.',
        );
      }
    });

    test(
      'אין שיטות־עזר של גלילה עצמאית (queue/flush/apply pointer scroll)',
      () {
        // השמות האלה נשארו כ"טביעות אצבע" של המימוש הישן שהוסר —
        // אם מישהו מחזיר אותם, הוא מחזיר גם את הבאג.
        const forbiddenSymbols = [
          '_queuePointerScroll',
          '_flushQueuedPointerScroll',
          '_applyPointerScrollDelta',
          '_applyPanZoomScroll',
          '_pendingPointerScrollDx',
          '_pendingPointerScrollDy',
          '_panZoomBaseMatrix',
          '_pointerScrollFlushDelay',
          '_maxPointerScrollBurstDelta',
        ];
        for (final symbol in forbiddenSymbols) {
          expect(
            source.contains(symbol),
            isFalse,
            reason:
                'הסמל $symbol הוא חלק ממימוש גלילה עצמאית שהוסר בקומיט '
                '3f6600693335d04d38754abf7ab8cbfb21d1c032. '
                'אסור להחזיר אותו — אם יש בעיה בגלילה, פתור אותה דרך פרמטרים '
                'של pdfrx (scrollByMouseWheel וכו\').',
          );
        }
      },
    );

    test(
      'onPointerSignal רק מאציל ל-handlePointerSignalEvent, ולא מבצע translate ידני',
      () {
        // המימוש הלגיטימי היחיד הוא להאציל ל-API של pdfrx
        // (handlePointerSignalEvent) — לא לחשב delta ולקרוא ל-goTo.
        expect(
          source.contains('handlePointerSignalEvent'),
          isTrue,
          reason:
              'onPointerSignal חייב להאציל ל-pdfViewerController.handlePointerSignalEvent — '
              'זוהי הדרך הנתמכת לטיפול בגלגלת כאשר ה-overlay תופס את האירוע.',
        );

        // איתור הבלוק של onPointerSignal ובדיקה שאין בו translate/goTo
        // המבוצעים בתגובה ל-PointerScrollEvent.
        final blockMatch = RegExp(
          r'onPointerSignal\s*:\s*\([^)]*\)\s*(?:=>\s*[^,;\n]+|\{)',
        ).firstMatch(source);
        if (blockMatch != null) {
          // קח חתיכה רחבה מספיק שתכסה גוף Lambda רגיל.
          final start = blockMatch.start;
          final slice = source.substring(
            start,
            (start + 600).clamp(0, source.length),
          );

          // השילובים האלה מעידים על חישוב גלילה ידני מתוך onPointerSignal.
          expect(
            slice.contains('translateByDouble'),
            isFalse,
            reason:
                'תוך onPointerSignal אסור להפעיל translateByDouble על ה-matrix — '
                'זה בדיוק המימוש העצמאי שהוסר.',
          );
          expect(
            RegExp(r'pdfViewerController\.goTo\s*\(').hasMatch(slice),
            isFalse,
            reason:
                'תוך onPointerSignal אסור לקרוא ל-pdfViewerController.goTo — '
                'יש להעביר את האירוע ל-handlePointerSignalEvent.',
          );
        }
      },
    );
  });
}

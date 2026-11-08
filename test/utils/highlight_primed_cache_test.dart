import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show HighlightPattern;

import '../support/search_engine_test_init.dart';

/// המטמון המוזן-מראש של תבניות ההדגשה (primeHighlightPattern):
///
/// הבאג: fetch שמחזיר null (למשל כשהמנוע לא הפיק תבנית מהאינדקס) נשמר
/// במטמון כ-null תחת מפתח השאילתה. _resolveHighlightPattern מעדיף רשומה
/// מוזנת-מראש לפי containsKey — ולכן ה-null החוסם גובר על מסלול ה-fallback
/// המקומי (generateHighlightPattern) לתמיד, וגם ניסיון הזנה חוזר נחסם באותו
/// containsKey. התוצאה: לשאילתה אין שום הדגשה בספר, למרות שה-fallback היה
/// מדגיש אותה.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group(
    'primeHighlightPattern מול fetch שמחזיר null',
    () {
      // המטמון גלובלי לקובץ (isolate) — כל טסט משתמש בשאילתה משלו.

      test('null אינו חוסם את ה-fallback המקומי', () async {
        const query = 'זרעך';
        await primeHighlightPattern(
          searchQuery: query,
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => null,
        );

        final marked = highLight('ידע תדע כי גר יהיה זרעך', query);
        expect(
          marked,
          contains('<span style="color: otzaria-search-hit">זרעך</span>'),
          reason: 'בהיעדר תבנית מהמנוע ה-fallback חייב להמשיך לשרת',
        );
      });

      test('הזנה חוזרת אחרי null נכנסת לתוקף', () async {
        const query = 'גאולה';
        await primeHighlightPattern(
          searchQuery: query,
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => null,
        );
        // תבנית שמדגישה מילה אחרת מהשאילתה — הדגשת "ישועה" מוכיחה
        // שדווקא התבנית המוזנת (ולא ה-fallback של "גאולה") בשימוש.
        await primeHighlightPattern(
          searchQuery: query,
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => const HighlightPattern(
            combinedPattern: 'ישועה',
            wordPatterns: ['ישועה'],
            wordBoundaryEligible: [true],
          ),
        );

        final marked = highLight('קרובה ישועה לבוא', query);
        expect(
          marked,
          contains('<span style="color: otzaria-search-hit">ישועה</span>'),
          reason: 'רשומת null אסור לה לחסום הזנה מוצלחת מאוחרת יותר',
        );
      });

      test('תבנית מוזנת תקינה קודמת ל-fallback (התנהגות קיימת)', () async {
        const query = 'תפילה';
        await primeHighlightPattern(
          searchQuery: query,
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => const HighlightPattern(
            combinedPattern: 'תחינה',
            wordPatterns: ['תחינה'],
            wordBoundaryEligible: [true],
          ),
        );

        final marked = highLight('נשא תחינה ובקשה', query);
        expect(
          marked,
          contains('<span style="color: otzaria-search-hit">תחינה</span>'),
        );
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}

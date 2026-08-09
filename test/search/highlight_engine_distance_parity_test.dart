import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

/// שקילות בין מה שמנוע החיפוש מוצא לבין מה שההדגשה בצד האפליקציה מסמנת.
///
/// חלונית החיפוש בספר מציגה את תוצאות המנוע, ופאנל הקריאה מדגיש לפי תבנית
/// ההדגשה. כששני הצדדים סופרים מילים אחרת, המשתמש רואה מילים מודגשות ולידן
/// "אין תוצאות" — לכן כל טקסט נבדק כאן בשני הצדדים באותם מרווחים בדיוק.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('פריטי מנוע ↔ הדגשה', () {
    late Directory indexDir;
    late SearchEngine engine;

    const samples = <String, String>{
      'gap1': 'אלף בית גימל',
      'gap2': 'אלף בית גימל דלת',
      'maqaf': 'תדע כי־גר יהיה זרעך',
      'maqafPlain': 'תדע כי גר יהיה זרעך',
      'pasek': 'תדע כי ׀ גר זרעך',
    };

    setUpAll(() async {
      if (!engineReady) return;
      indexDir = Directory.systemTemp.createTempSync('highlight_parity');
      engine = SearchEngine(path: indexDir.path);
      var id = 1;
      for (final entry in samples.entries) {
        await engine.addDocument(
          id: BigInt.from(id),
          title: entry.key,
          reference: entry.key,
          topics: '/parity/${entry.key}',
          text: entry.value,
          segment: BigInt.from(id),
          isPdf: false,
          filePath: 'id:$id',
        );
        id++;
      }
      await engine.commit();
    });

    tearDownAll(() {
      if (!engineReady) return;
      engine.dispose();
      // Tantivy ממפה את קבצי האינדקס לזיכרון, וב-Windows המחיקה נכשלת עד
      // ששחרור המיפוי מגיע בפועל; תיקיית ה-temp מנוקה ע"י המערכת ממילא.
      try {
        indexDir.deleteSync(recursive: true);
      } on FileSystemException {
        return;
      }
    });

    Future<bool> engineFinds(String sample, String query, int distance) async {
      final results = await engine.searchAdvanced(
        query: query,
        negativeQuery: '',
        facets: ['/parity/$sample'],
        limit: 10,
        offset: 0,
        distance: distance,
        negativeDistance: 0,
        customSpacing: const {},
        negativeCustomSpacing: const {},
        alternativeWords: const {},
        negativeAlternativeWords: const {},
        searchOptions: const {},
        negativeSearchOptions: const {},
        order: ResultsOrder.catalogue,
        matchNikud: false,
        matchTaamim: false,
        scope: SearchScope.wordDistance,
        negativeScope: SearchScope.wordDistance,
      );
      return results.isNotEmpty;
    }

    bool highlightFinds(String text, String query, int distance) {
      return utils
          .computeHighlightRanges(text, query, searchDistance: distance)
          .isNotEmpty;
    }

    Future<void> expectParity(String sample, String query) async {
      final text = samples[sample]!;
      for (var distance = 0; distance <= 4; distance++) {
        final fromEngine = await engineFinds(sample, query, distance);
        final fromHighlight = highlightFinds(text, query, distance);
        expect(
          fromHighlight,
          fromEngine,
          reason:
              'טקסט "$text", שאילתה "$query", מרווח $distance: '
              'מנוע=$fromEngine, הדגשה=$fromHighlight',
        );
      }
    }

    test('מילים רגילות במרווח מילה', () => expectParity('gap1', 'אלף גימל'));

    test('מילים רגילות במרווח שתי מילים', () {
      return expectParity('gap2', 'אלף דלת');
    });

    test('מקף בין מילות הפער נספר כשתי מילים (הבאג המקורי)', () {
      // "תדע כי־גר יהיה זרעך": האינדקס מפצל את "כי־גר" לשתיים ולכן דורש
      // מרווח 3, ואילו ההדגשה סימנה כבר במרווח 2 — הדגשה בלי תוצאות.
      return expectParity('maqaf', 'תדע זרעך');
    });

    test('אותו טקסט עם רווח במקום מקף', () {
      return expectParity('maqafPlain', 'תדע זרעך');
    });

    test('פסק בין המילים אינו נספר כמילה', () {
      return expectParity('pasek', 'תדע זרעך');
    });

    test('שאילתה שהמקף חלק ממנה מודגשת בטקסט המקורי', () async {
      // המקף בטקסט הוא מפריד מילים כמו באינדקס, ולכן שאילתת שתי המילים
      // מותאמת גם כשבטקסט הן מחוברות במקף.
      expect(await engineFinds('maqaf', 'כי גר', 0), isTrue);
      expect(highlightFinds(samples['maqaf']!, 'כי גר', 0), isTrue);
    });

    test('ההדגשה מחזירה היסטים של הטקסט המקורי (המקף נשמר)', () {
      const text = 'תדע כי־גר יהיה זרעך';
      final ranges = utils.computeHighlightRanges(
        text,
        'כי גר',
        searchDistance: 0,
      );
      expect(ranges, isNotEmpty);
      final marked = [
        for (final range in ranges) text.substring(range[0], range[1]),
      ];
      expect(marked, ['כי', 'גר']);

      final highlighted = utils.highLight(text, 'כי גר');
      expect(highlighted, contains('־'));
      expect(highlighted, contains('<span style="color: red">כי</span>'));
      expect(highlighted, contains('<span style="color: red">גר</span>'));
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}

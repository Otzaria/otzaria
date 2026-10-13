import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show HighlightPattern;

import '../support/recording_search_engine.dart';
import '../support/search_engine_test_init.dart';

/// שם הוי"ה בכתיב escapes, כדי שלא ייכתב בקוד המקור.
const _name = 'יהוה';
const _placeholder = 'יקוק';

/// פורום אוצריא, נושא 981: "יקוק" שהועתק מהתצוגה לא מצא את השם עצמו.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('withHolyNameAlternatives', () {
    test('מוסיף את השם כחלופה למילת "יקוק", עם אותיות השימוש שלפניה', () {
      expect(withHolyNameAlternatives('$_placeholder אלהינו', const {}), {
        0: [_name],
      });
      expect(withHolyNameAlternatives('יודו ל$_placeholder חסדו', const {}), {
        1: ['ל$_name'],
      });
    });

    test('משמר חלופות קיימות ואינו משכפל בקריאה חוזרת', () {
      final once = withHolyNameAlternatives('$_placeholder אחד', const {
        0: ['אדני'],
        1: ['יחיד'],
      });
      expect(once, {
        0: ['אדני', _name],
        1: ['יחיד'],
      });
      expect(withHolyNameAlternatives('$_placeholder אחד', once), once);
    });

    test('שאילתה בלי "יקוק" כמילה שלמה חוזרת כמות שהיא', () {
      const alternatives = {
        0: ['א'],
      };
      for (final query in [
        'שלום עולם',
        '$_placeholderים',
        'אבג$_placeholder',
      ]) {
        expect(
          identical(
            withHolyNameAlternatives(query, alternatives),
            alternatives,
          ),
          isTrue,
          reason: query,
        );
      }
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  group('SearchEngineGateway', () {
    const gateway = SearchEngineGateway();

    test('חיפוש רגיל עם "יקוק" עובר למתקדם עם השם כחלופה', () async {
      final engine = RecordingSearchEngine();
      await gateway.search(
        engine,
        const SearchEngineRequest(query: '$_placeholder אלהינו', facets: ['/']),
      );
      expect(engine.lastRequest!.searchMode, SearchMode.advanced);
      expect(engine.lastRequest!.alternativeWords, {
        0: [_name],
      });
    });

    test('חיפוש מתקדם שומר את המצב ומוסיף את החלופה', () async {
      final engine = RecordingSearchEngine();
      await gateway.search(
        engine,
        const SearchEngineRequest(
          query: 'ברוך $_placeholder',
          facets: ['/'],
          searchMode: SearchMode.advanced,
          distance: 3,
        ),
      );
      expect(engine.lastRequest!.searchMode, SearchMode.advanced);
      expect(engine.lastRequest!.distance, 3);
      expect(engine.lastRequest!.alternativeWords, {
        1: [_name],
      });
    });

    test('מעבר למתקדם משמר את "בכל סדר"', () async {
      final engine = RecordingSearchEngine();
      await gateway.search(
        engine,
        const SearchEngineRequest(
          query: '$_placeholder אלהינו',
          facets: ['/'],
          anyOrder: true,
        ),
      );
      expect(engine.lastRequest!.searchMode, SearchMode.advanced);
      expect(engine.lastRequest!.anyOrder, isTrue);
    });

    test('חיפוש בלי "יקוק" ומקורב אינם משתנים', () async {
      final engine = RecordingSearchEngine();
      const plain = SearchEngineRequest(query: 'שלום עולם', facets: ['/']);
      await gateway.search(engine, plain);
      expect(identical(engine.lastRequest, plain), isTrue);

      const fuzzy = SearchEngineRequest(
        query: '$_placeholder אלהינו',
        facets: ['/'],
        searchMode: SearchMode.fuzzy,
      );
      await gateway.search(engine, fuzzy);
      expect(identical(engine.lastRequest, fuzzy), isTrue);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  test(
    'בספר פתוח "יקוק" שהוקלד מדגיש את השם, גם כשהתצוגה מחליפה אותו',
    () {
      const line = 'יודו ל$_name חסדו';
      final out = TextRendererService.processText(
        line,
        const RenderSettings(
          searchText: 'יודו ל$_placeholder חסדו',
          replaceHolyNames: true,
        ),
      );
      expect(out, isNot(contains(_name)));
      expect(out, contains('<span style="color: red">יודו</span>'));
      expect(out, contains('<span style="color: red">חסדו</span>'));
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  group('הערות הביקורת', () {
    test('מילה מנוקדת ו"יקוק" בתוך רשימת החלופות מורחבים גם הם', () {
      expect(
        withHolyNameAlternatives('לַיקֹוָק', const {}),
        {
          // הניקוד שהוקלד נשמר בחלופה, כדי שהתאמת ניקוד לא תתרחב.
          0: ['לַיהֹוָה'],
        },
      );
      expect(
        withHolyNameAlternatives('אדני', const {
          0: [_placeholder],
        }),
        {
          0: [_placeholder, _name],
        },
      );
    });

    test('השאילתה השלילית מורחבת כמו החיובית', () async {
      final engine = RecordingSearchEngine();
      await const SearchEngineGateway().search(
        engine,
        const SearchEngineRequest(
          query: 'ברוך',
          negativeQuery: _placeholder,
          facets: ['/'],
          searchMode: SearchMode.advanced,
        ),
      );
      expect(engine.lastRequest!.negativeAlternativeWords, {
        0: [_name],
      });
    });

    test('במקורב ההדגשה נשענת על התבנית שהמנוע הכין, בלי הרחבה', () async {
      const query = '$_placeholder אלהינו';
      await primeHighlightPattern(
        searchQuery: query,
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: true,
        fetch: () async => const HighlightPattern(
          combinedPattern: 'ברא',
          wordPatterns: ['ברא'],
          wordBoundaryEligible: [true],
        ),
      );
      expect(
        highLight('בראשית ברא אלהים', query, isFuzzy: true),
        contains('<span style="color: red">ברא</span>'),
      );
    });

    test('החיפוש הליטרלי בספר מוצא את השם כשהוקלד "יקוק"', () {
      for (final wholeWord in [true, false]) {
        final pattern = buildLiteralPattern(
          'ל$_placeholder אלהינו',
          wholeWord: wholeWord,
        )!;
        expect(pattern.regExp.hasMatch('שירו ל$_name אלהינו'), isTrue);
        expect(pattern.regExp.hasMatch('שירו ל$_placeholder אלהינו'), isTrue);
        expect(pattern.regExp.hasMatch('שירו אלהינו'), isFalse);
      }
    });

    test('בחיפוש בספר כל מופע של "יקוק" מוחלף בנפרד', () {
      for (final wholeWord in [true, false]) {
        final pattern = buildLiteralPattern(
          '$_placeholder אחד $_placeholder',
          wholeWord: wholeWord,
        )!;
        for (final first in [_placeholder, _name]) {
          for (final second in [_placeholder, _name]) {
            expect(
              pattern.regExp.hasMatch('$first אחד $second'),
              isTrue,
              reason: 'wholeWord=$wholeWord',
            );
          }
        }
      }
    });

    test('קרי וכתיב אינם מבטלים הרחבת מופעים בהמשך החיפוש המקומי', () {
      for (final wholeWord in [true, false]) {
        for (final reading in ['אדני', _placeholder, 'אבג$_placeholder']) {
          final query =
              '($_placeholder) [$reading] ל$_placeholder ${_placeholder}2';
          final pattern = buildLiteralPattern(query, wholeWord: wholeWord)!;
          final expandedReading = reading == _placeholder ? _name : reading;
          expect(pattern.regExp.hasMatch(query), isTrue);
          expect(
            pattern.regExp.hasMatch(
              '($_placeholder) [$expandedReading] ל$_name ${_placeholder}2',
            ),
            isTrue,
            reason: '$query / wholeWord=$wholeWord',
          );
          expect(
            pattern.regExp.hasMatch(
              '($_name) [$expandedReading] ל$_name ${_placeholder}2',
            ),
            isFalse,
          );
          expect(
            pattern.regExp.hasMatch(
              '($_placeholder) [$expandedReading] ל$_name ${_name}2',
            ),
            isFalse,
          );
        }
      }
    });

    test('פיסוק שקוף במילה קודמת אינו מבטל הרחבת מופע תקין', () {
      for (final wholeWord in [true, false]) {
        final query = 'יקו[ק] $_placeholder';
        final pattern = buildLiteralPattern(query, wholeWord: wholeWord)!;
        expect(pattern.regExp.hasMatch(query), isTrue);
        expect(pattern.regExp.hasMatch('יקו[ק] $_name'), isTrue);
      }
    });

    test('מיקומי המקור נשארים נכונים אחרי תו Unicode שאורכו שתי יחידות', () {
      final query = '😀 ($_placeholder) [אדני] $_placeholder';
      for (final wholeWord in [true, false]) {
        final pattern = buildLiteralPattern(query, wholeWord: wholeWord)!;
        expect(
          pattern.regExp.hasMatch('😀 ($_placeholder) [אדני] $_name'),
          isTrue,
        );
        expect(pattern.regExp.hasMatch('😀 ($_name) [אדני] $_name'), isFalse);
      }
    });

    test('שני המסלולים מזהים את מילת "יקוק" לפי אותו כלל', () {
      const query = '${_placeholder}2';
      expect(withHolyNameAlternatives(query, const {}), isEmpty);
      final pattern = buildLiteralPattern(query)!;
      expect(pattern.regExp.hasMatch('${_placeholder}2'), isTrue);
      expect(pattern.regExp.hasMatch('${_name}2'), isFalse);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}

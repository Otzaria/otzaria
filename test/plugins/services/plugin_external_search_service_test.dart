import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/search/models/search_match_policy.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

void main() {
  group('sanitizeIndex', () {
    final service = PluginExternalSearchService.instance;

    test('מקבל רשומות [id, hits] ו-[id, hits, category]', () {
      final entries = service.sanitizeIndexForTesting([
        [43558, 7, '/שו"ת'],
        [12, 0],
      ])!;
      expect(entries, hasLength(2));
      expect(entries[0].id, 43558);
      expect(entries[0].hits, 7);
      expect(entries[0].categoryPath, '/שו"ת');
      expect(entries[1].categoryPath, isNull);
      expect(entries[0].title, isNull);
    });

    test('מקבל שם ספר כאיבר רביעי, עם קטגוריה ובלעדיה', () {
      final entries = service.sanitizeIndexForTesting([
        [43558, 7, '/שו"ת', 'שאלות ותשובות'],
        [44, 2, '', 'ספר בלי סיווג'],
      ])!;
      expect(entries[0].categoryPath, '/שו"ת');
      expect(entries[0].title, 'שאלות ותשובות');
      expect(entries[1].categoryPath, isNull);
      expect(entries[1].title, 'ספר בלי סיווג');
    });

    test('זורק רשומות פגומות ומנקה נתיבים לא תקינים', () {
      final entries = service.sanitizeIndexForTesting([
        'לא רשומה',
        [0, 5],
        [5, -1],
        [5],
        [5, 1, 2, 3, 4],
        [6, 3, 2, 3],
        [7, 3, 'בלי לוכסן'],
        [8, 3, '/'],
        [9, 3, '/הלכה\u0000'],
      ])!;
      expect(entries.map((e) => e.id), [6, 7, 8, 9]);
      // איבר שאינו מחרוזת נזרק, והרשומה נשארת בלי סיווג ובלי שם.
      expect(entries[0].categoryPath, isNull);
      expect(entries[0].title, isNull);
      expect(entries[1].categoryPath, isNull);
      expect(entries[2].categoryPath, isNull);
      expect(entries[3].categoryPath, '/הלכה');
    });

    test('null נשאר null — עדכון בלי אינדקס אינו מוחק אינדקס קודם', () {
      expect(service.sanitizeIndexForTesting(null), isNull);
      expect(service.sanitizeIndexForTesting(const []), isEmpty);
    });
  });

  group('provider ownership', () {
    late PluginExternalSearchService service;
    late Map<String, dynamic> request;

    setUp(() {
      service = PluginExternalSearchService.forTesting(
        (pluginId, topic, payload, {preferBackground = false}) async {
          request = payload;
        },
      );
    });

    test('תוסף אחר אינו יכול לדרוס ספק רשום', () {
      service.register('hebrewbooks', 'owner');

      expect(
        () => service.register('hebrewbooks', 'attacker'),
        throwsStateError,
      );
      expect(service.hasProvider('hebrewbooks'), isTrue);
    });

    test('הבקשה מצהירה שהקורא צורך שמות ספרים באינדקס', () async {
      service.register('hebrewbooks', 'owner');
      final search = service.search(provider: 'hebrewbooks', query: 'שלום');
      await Future<void>.delayed(Duration.zero);
      expect(request['indexTitles'], isTrue);
      expect(search, throwsStateError);
      service.removePlugin('owner');
    });

    test(
      'אפשרויות מילה פעילות נשלחות באירוע; מפה ריקה משמיטה את השדה',
      () async {
        service.register('hebrewbooks', 'owner');
        final withOptions = service.search(
          provider: 'hebrewbooks',
          query: 'ברכת המזון',
          options: const {'קידומות דקדוקיות': true},
          wordOptions: const {
            'ברכת_0': {'קידומות דקדוקיות': true},
            'המזון_1': {'קידומות דקדוקיות': true},
          },
        );
        await Future<void>.delayed(Duration.zero);
        expect(request['options'], {'קידומות דקדוקיות': true});
        expect(request['wordOptions'], {
          'ברכת_0': {'קידומות דקדוקיות': true},
          'המזון_1': {'קידומות דקדוקיות': true},
        });
        expect(withOptions, throwsStateError);

        final withoutOptions = service.search(
          provider: 'hebrewbooks',
          query: 'ברכת המזון',
        );
        await Future<void>.delayed(Duration.zero);
        expect(request.containsKey('options'), isFalse);
        expect(request.containsKey('wordOptions'), isFalse);
        expect(withoutOptions, throwsStateError);
        service.removePlugin('owner');
      },
    );

    test('מדיניות ההתאמה נשלחת באירוע; ברירת המחדל היא מרווח מילים', () async {
      service.register('hebrewbooks', 'owner');
      final withPolicy = service.search(
        provider: 'hebrewbooks',
        query: 'ברכת המזון',
        matchPolicy: const SearchMatchPolicy(
          proximityScope: SearchScope.sameParagraph,
          wordMatchMode: WordMatchMode.atLeast,
          wordMatchCount: 3,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(request['proximityScope'], 'sameParagraph');
      expect(request['wordMatchMode'], 'atLeast');
      expect(request['wordMatchCount'], 3);
      expect(withPolicy, throwsStateError);

      final standard = service.search(
        provider: 'hebrewbooks',
        query: 'ברכת המזון',
      );
      await Future<void>.delayed(Duration.zero);
      expect(request['proximityScope'], 'wordDistance');
      expect(request['wordMatchMode'], 'all');
      expect(request.containsKey('anyOrder'), isFalse);
      expect(standard, throwsStateError);

      final anyOrder = service.search(
        provider: 'hebrewbooks',
        query: 'ברכת המזון',
        matchPolicy: const SearchMatchPolicy(anyOrder: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(request['anyOrder'], isTrue);
      expect(anyOrder, throwsStateError);
      service.removePlugin('owner');
    });

    test(
      'עמוד המשך ועמוד לפי מזהים אינם מזמינים שמות — אין בהם אינדקס',
      () async {
        service.register('hebrewbooks', 'owner');
        final next = service.search(
          provider: 'hebrewbooks',
          query: 'שלום',
          offset: 20,
        );
        await Future<void>.delayed(Duration.zero);
        expect(request.containsKey('indexTitles'), isFalse);
        expect(next, throwsStateError);

        final byIds = service.search(
          provider: 'hebrewbooks',
          query: 'שלום',
          ids: const [1, 2],
        );
        await Future<void>.delayed(Duration.zero);
        expect(request.containsKey('indexTitles'), isFalse);
        expect(byIds, throwsStateError);
        service.removePlugin('owner');
      },
    );

    test('רק בעל הספק יכול לענות לבקשה', () async {
      service.register('hebrewbooks', 'owner');
      final search = service.search(
        provider: 'hebrewbooks',
        query: 'שלום',
      );
      await Future<void>.delayed(Duration.zero);
      final requestId = request['requestId'] as String;
      var completed = false;
      unawaited(search.then((_) => completed = true));

      expect(service.respond('attacker', requestId), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      expect(
        service.respond(
          'owner',
          requestId,
          results: const [
            {'title': 'ספר', 'externalId': 1},
          ],
          totalBooks: 1,
        ),
        isTrue,
      );
      final page = await search;
      expect(page.results.single.title, 'ספר');
    });

    test('הסרת תוסף מפנה את הספק ומכשילה בקשה פעילה', () async {
      service.register('hebrewbooks', 'owner');
      final search = service.search(
        provider: 'hebrewbooks',
        query: 'שלום',
      );
      final expectation = expectLater(search, throwsStateError);

      service.removePlugin('owner');

      await expectation;
      expect(service.hasProvider('hebrewbooks'), isFalse);
    });
  });

  group('instance binding', () {
    late PluginExternalSearchService service;
    late Map<String, dynamic> request;

    setUp(() {
      service = PluginExternalSearchService.forTesting(
        (pluginId, topic, payload, {preferBackground = false}) async {
          request = payload;
        },
      );
      service.register('hebrewbooks', 'owner');
    });

    tearDown(() => service.removePlugin('owner'));

    test('הבקשה ננעלת למופע העונה הראשון — מופע אחר נדחה בלי כפולים', () async {
      final updates = <ExternalSearchPage>[];
      final search = service.search(
        provider: 'hebrewbooks',
        query: 'שלום',
        onUpdate: updates.add,
      );
      await Future<void>.delayed(Duration.zero);
      final requestId = request['requestId'] as String;

      expect(
        service.respond(
          'owner',
          requestId,
          results: const [
            {'title': 'ספר א', 'externalId': 1},
          ],
          totalBooks: 1,
          done: false,
          instanceId: 'tab-1',
        ),
        isTrue,
      );
      // אותו requestId ממופע אחר — נדחה, גם במסלול הזרימה.
      expect(
        service.respond(
          'owner',
          requestId,
          results: const [
            {'title': 'ספר כפול', 'externalId': 2},
          ],
          totalBooks: 2,
          done: false,
          instanceId: 'tab-2',
        ),
        isFalse,
      );
      expect(updates, hasLength(1));

      expect(
        service.respond(
          'owner',
          requestId,
          results: const [
            {'title': 'ספר א', 'externalId': 1},
          ],
          totalBooks: 1,
          instanceId: 'tab-1',
        ),
        isTrue,
      );
      final page = await search;
      expect(page.results.single.externalId, 1);
    });

    test('תשובה בלי instanceId מתקבלת גם אחרי נעילה (תאימות לאחור)', () async {
      final search = service.search(provider: 'hebrewbooks', query: 'שלום');
      await Future<void>.delayed(Duration.zero);
      final requestId = request['requestId'] as String;

      expect(
        service.respond(
          'owner',
          requestId,
          results: const [],
          done: false,
          instanceId: 'tab-1',
        ),
        isTrue,
      );
      expect(
        service.respond(
          'owner',
          requestId,
          results: const [
            {'title': 'ספר', 'externalId': 3},
          ],
          totalBooks: 1,
        ),
        isTrue,
      );
      final page = await search;
      expect(page.results.single.externalId, 3);
    });
  });
}

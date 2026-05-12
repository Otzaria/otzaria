import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';

void main() {
  tearDown(() async {
    await resetSectionSearchWorkerForTesting();
  });

  group('searchInContent - whole word matching', () {
    test('finds exact whole-word match', () async {
      final results = await searchInContent(
        content: ['שמע ישראל'],
        query: 'שמע',
      );
      expect(results.length, 1);
    });

    test('does not match partial word (query is prefix of longer word)', () async {
      final results = await searchInContent(
        content: ['שמעון'],
        query: 'שמע',
      );
      expect(results, isEmpty);
    });

    test('does not match partial word (query is suffix of longer word)', () async {
      final results = await searchInContent(
        content: ['ושמע'],
        query: 'שמע',
      );
      expect(results, isEmpty);
    });

    test('does not match partial word (query is infix of longer word)', () async {
      final results = await searchInContent(
        content: ['ושמעון'],
        query: 'שמע',
      );
      expect(results, isEmpty);
    });

    test('finds word at beginning of line', () async {
      final results = await searchInContent(
        content: ['ישראל עם'],
        query: 'ישראל',
      );
      expect(results.length, 1);
    });

    test('finds word at end of line', () async {
      final results = await searchInContent(
        content: ['עם ישראל'],
        query: 'ישראל',
      );
      expect(results.length, 1);
    });

    test('finds word surrounded by punctuation', () async {
      final results = await searchInContent(
        content: ['(שמע)'],
        query: 'שמע',
      );
      expect(results.length, 1);
    });

    test('does not match when query appears only as partial in all occurrences', () async {
      final results = await searchInContent(
        content: ['שמעון ושמעיהו'],
        query: 'שמע',
      );
      expect(results, isEmpty);
    });

    test('finds match when one occurrence is whole word and another is partial', () async {
      final results = await searchInContent(
        content: ['שמע ושמעון'],
        query: 'שמע',
      );
      expect(results.length, 1);
    });

    test('returns empty for empty content', () async {
      final results = await searchInContent(
        content: [],
        query: 'שמע',
      );
      expect(results, isEmpty);
    });

    test('returns empty for empty query', () async {
      final results = await searchInContent(
        content: ['שמע ישראל'],
        query: '',
      );
      expect(results, isEmpty);
    });
  });
}

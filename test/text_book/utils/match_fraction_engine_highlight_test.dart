import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_match_policy.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../../support/search_engine_test_init.dart';

/// הגלילה אל ההופעה מחושבת באותה תבנית שבה הספר מדגיש, גם בחיפוש עם מרווח.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  // רשב"א בערך באמצע השורה, וגיטין שלוש מילים אחריו.
  final line = [
    for (var i = 0; i < 40; i++) 'מילה',
    'הרשב"א',
    'כתב',
    'בזה',
    'בפרק',
    'גיטין',
    for (var i = 0; i < 40; i++) 'סוף',
  ].join(' ');
  final expected = line.indexOf('רשב"א') / line.length;

  group('גלילה אל ההופעה בחיפוש עם מרווח (issue #1642)', () {
    test(
      'מרחק בין מילים: השבר נגזר מתבנית ההדגשה ולא מהשאילתה הרצופה',
      () {
        final fraction = matchFractionInLine(
          line,
          'רשב"א גיטין',
          searchDistance: 30,
          searchOptions: const {
            'רשב"א_0': {'קידומות': true},
          },
        );
        expect(fraction, closeTo(expected, 0.001));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'שאילתה רצופה בלי אפשרויות: השבר לפי תחילת הביטוי',
      () {
        final fraction = matchFractionInLine(line, 'בפרק גיטין');
        expect(fraction, closeTo(line.indexOf('בפרק') / line.length, 0.001));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  // ציטוט חלקי (ארבע מתוך חמש המילים) לפני ההתאמה המלאה, כמו בתורת הבית.
  const query = 'בסמוך בוסת הדילוג אמרינן דשמואל';
  final options = {
    for (final (i, word) in query.split(' ').indexed)
      '${word}_$i': const {'קידומות': true, 'כתיב מלא/חסר': true},
  };
  final quotedLine = [
    for (var i = 0; i < 30; i++) 'פתיחה',
    'וכדאמרינן בוסת הדילוג אמרינן דשמואל',
    for (var i = 0; i < 60; i++) 'אמצע',
    'וכדכתבינן בסמוך בוסת הדילוג אמרינן דשמואל',
    for (var i = 0; i < 30; i++) 'סוף',
  ].join(' ');
  final fullMatch = quotedLine.indexOf('בסמוך') / quotedLine.length;

  group('גלילה אל ההתאמה המלאה ולא לציטוט חלקי (issue #5757)', () {
    for (final (name, policy) in [
      (
        'באותה פסקה',
        SearchMatchPolicy(proximityScope: SearchScope.sameParagraph),
      ),
      ('רוב המילים', SearchMatchPolicy(wordMatchMode: WordMatchMode.mostWords)),
      ('בכל סדר', SearchMatchPolicy(anyOrder: true)),
    ]) {
      test(
        '$name: השבר לפי הביטוי השלם ולא לפי המילה המודגשת הראשונה',
        () {
          final fraction = matchFractionInLine(
            quotedLine,
            query,
            searchOptions: options,
            matchPolicy: policy,
          );
          expect(fraction, closeTo(fullMatch, 0.001));
        },
        skip: engineReady ? false : searchEngineSkipReason,
      );
    }

    test(
      'בכל סדר: הביטוי השלם נמצא גם כשהמילים מופיעות בסדר הפוך',
      () {
        final reversed = query.split(' ').reversed.join(' ');
        final line = quotedLine.replaceFirst(query, reversed);
        final fraction = matchFractionInLine(
          line,
          query,
          searchOptions: options,
          matchPolicy: const SearchMatchPolicy(anyOrder: true),
        );
        expect(fraction, closeTo(line.indexOf(reversed) / line.length, 0.001));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'בלי הביטוי השלם בשורה: השבר לפי המילה המודגשת הראשונה, כמו קודם',
      () {
        final partialOnly = quotedLine.replaceFirst('בסמוך ', '');
        final fraction = matchFractionInLine(
          partialOnly,
          query,
          searchOptions: options,
          matchPolicy: const SearchMatchPolicy(
            proximityScope: SearchScope.sameParagraph,
          ),
        );
        expect(
          fraction,
          closeTo(partialOnly.indexOf('אמרינן') / partialOnly.length, 0.001),
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'מרווח רגיל: הציטוט החלקי אינו מודגש ולכן השבר לפי הביטוי השלם',
      () {
        final fraction = matchFractionInLine(
          quotedLine,
          query,
          searchOptions: options,
        );
        expect(fraction, closeTo(fullMatch, 0.001));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });
}

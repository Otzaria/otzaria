import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope;

void main() {
  group('RenderSettings equality', () {
    test('hashCode is independent of map insertion order', () {
      final first = RenderSettings(
        searchText: 'אמר רבי',
        searchOptions: {
          'אמר_0': {'סיומות': true, 'תחיליות': false},
          'רבי_1': {'כתיב': true},
        },
        alternativeWords: {
          0: ['ויאמר', 'אמר'],
          1: ['רבנו'],
        },
        spacingValues: {'0-1': '2', '1-2': '5'},
      );
      final reversed = RenderSettings(
        searchText: 'אמר רבי',
        searchOptions: {
          'רבי_1': {'כתיב': true},
          'אמר_0': {'תחיליות': false, 'סיומות': true},
        },
        alternativeWords: {
          1: ['רבנו'],
          0: ['ויאמר', 'אמר'],
        },
        spacingValues: {'1-2': '5', '0-1': '2'},
      );

      expect(first, equals(reversed));
      expect(first.hashCode, reversed.hashCode);
    });

    test('large maps preserve equality and hash across insertion order', () {
      final names = List.generate(200, (i) => 'word_$i');
      final left = RenderSettings(
        searchOptions: {
          for (final name in names)
            name: {'exact': true, 'fuzzy': false},
        },
        alternativeWords: {
          for (var i = 0; i < names.length; i++)
            i: [names[i], 'alternative_$i'],
        },
        spacingValues: {
          for (var i = 0; i < names.length; i++)
            'distance_$i': '$i',
        },
      );
      final right = RenderSettings(
        searchOptions: {
          for (final name in names.reversed)
            name: {'fuzzy': false, 'exact': true},
        },
        alternativeWords: {
          for (var i = names.length - 1; i >= 0; i--)
            i: [names[i], 'alternative_$i'],
        },
        spacingValues: {
          for (var i = names.length - 1; i >= 0; i--)
            'distance_$i': '$i',
        },
      );

      expect(left, equals(right));
      expect(left.hashCode, right.hashCode);
    });

    test('alternative word order remains meaningful', () {
      const left = RenderSettings(alternativeWords: {
        0: ['אמר', 'ויאמר'],
      });
      const right = RenderSettings(alternativeWords: {
        0: ['ויאמר', 'אמר'],
      });
      expect(left, isNot(equals(right)));
    });

    test('changes when spacing values change', () {
      const withSpacing = RenderSettings(
        searchText: 'אמר רבי',
        spacingValues: {'0-1': '1'},
      );
      const withoutSpacing = RenderSettings(searchText: 'אמר רבי');

      expect(withSpacing, isNot(equals(withoutSpacing)));
      expect(withSpacing.hashCode, isNot(equals(withoutSpacing.hashCode)));
    });

    test('changes when advanced search options change', () {
      const withOptions = RenderSettings(
        searchText: 'אמר',
        searchOptions: {
          'אמר_0': {'סיומות': true},
        },
      );
      const withoutOptions = RenderSettings(searchText: 'אמר');

      expect(withOptions, isNot(equals(withoutOptions)));
      expect(withOptions.hashCode, isNot(equals(withoutOptions.hashCode)));
    });

    test('changes when alternative words change', () {
      const withAlternative = RenderSettings(
        searchText: 'אמר',
        alternativeWords: {
          0: ['ויאמר'],
        },
      );
      const withoutAlternative = RenderSettings(searchText: 'אמר');

      expect(withAlternative, isNot(equals(withoutAlternative)));
      expect(
        withAlternative.hashCode,
        isNot(equals(withoutAlternative.hashCode)),
      );
    });

    test('changes when match policy changes', () {
      // בלי המדיניות בשוויון, ה-widget של הטקסט לא היה מתרנן כשהמשתמש עובר
      // לחיפוש "באותה פסקה", והשורה הייתה נשארת בלי הדגשה.
      const sameParagraph = RenderSettings(
        searchText: 'אמר רבי',
        matchPolicy: SearchMatchPolicy(
          proximityScope: SearchScope.sameParagraph,
        ),
      );
      const wordDistance = RenderSettings(searchText: 'אמר רבי');

      expect(sameParagraph, isNot(equals(wordDistance)));
      expect(sameParagraph.hashCode, isNot(wordDistance.hashCode));
    });

    test('changes when holy name style changes', () {
      // בלי הסגנון בשוויון, מעבר בין יקוק ל-ה' לא היה מרענן טקסט מרונדר.
      const heh = RenderSettings(
        replaceHolyNames: true,
        holyNameStyle: HolyNameStyle.hehApostrophe,
      );
      const kuf = RenderSettings(replaceHolyNames: true);

      expect(heh, isNot(equals(kuf)));
      expect(heh.hashCode, isNot(equals(kuf.hashCode)));
      expect(kuf.copyWith(holyNameStyle: HolyNameStyle.hehApostrophe), heh);
    });

    test('changes when font weight changes', () {
      const bold = RenderSettings(fontWeight: FontWeight.bold);
      const regular = RenderSettings();

      expect(bold, isNot(equals(regular)));
      expect(bold.hashCode, isNot(equals(regular.hashCode)));
      expect(regular.fontWeight, isNull);
      expect(regular.copyWith(fontWeight: FontWeight.bold), equals(bold));
    });
  });
}

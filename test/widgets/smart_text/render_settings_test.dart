import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  group('RenderSettings equality', () {
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

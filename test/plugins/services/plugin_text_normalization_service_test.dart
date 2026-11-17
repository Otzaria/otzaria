import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';

void main() {
  const service = PluginTextNormalizationService();

  PluginNormalizedText normalize(
    String text,
    PluginNormalizationProfile profile, {
    Map<String, dynamic> overrides = const {},
    bool displayIgnoreNikud = false,
    bool displayIgnoreTeamim = false,
  }) {
    return service.normalize(
      text,
      PluginNormalizeOptions.forProfile(
        profile,
        overrides: overrides,
        displayIgnoreNikud: displayIgnoreNikud,
        displayIgnoreTeamim: displayIgnoreTeamim,
      ),
    );
  }

  test('strict preserves text and grapheme boundaries', () {
    final result = normalize(
      'אָב 👨‍👩‍👧‍👦',
      PluginNormalizationProfile.strict,
    );

    expect(result.text, 'אָב 👨‍👩‍👧‍👦');
    expect(result.sourceBoundaryByNormalizedGrapheme, [0, 1, 2, 3, 4]);
  });

  test('search removes nikud and teamim and collapses whitespace', () {
    final result = normalize(
      '  בְּרֵאשִׁ֖ית\n  בָּרָא  ',
      PluginNormalizationProfile.search,
    );

    expect(result.text, 'בראשית ברא');
    expect(result.sourceBoundary(0), 2);
    expect(result.sourceBoundary(result.text.characters.length), 14);
  });

  test('empty strict text retains its only source boundary', () {
    final result = normalize('', PluginNormalizationProfile.strict);

    expect(result.text, '');
    expect(result.sourceBoundaryByNormalizedGrapheme, [0]);
    expect(result.sourceEndByNormalizedGrapheme, isEmpty);
    expect(result.sourceEndBoundary(0), 0);
  });

  test(
    'strict keeps whitespace, marks and joined emoji as source graphemes',
    () {
      const source = ' \tאָ֑👨‍👩‍👧‍👦\r\n ';
      final result = normalize(source, PluginNormalizationProfile.strict);

      expect(result.text, source);
      expect(result.sourceBoundaryByNormalizedGrapheme, [0, 1, 2, 3, 4, 5, 6]);
      expect(result.sourceEndByNormalizedGrapheme, [1, 2, 3, 4, 5, 6]);
      expect(result.sourceEndBoundary(4), 4);
    },
  );

  test('disabling every lenient transformation preserves the source', () {
    const source = ' ךְ!🙂\n';
    final result = normalize(
      source,
      PluginNormalizationProfile.lenient,
      overrides: const {
        'ignoreNikud': false,
        'ignoreTeamim': false,
        'ignorePunctuation': false,
        'normalizeWhitespace': false,
        'normalizeFinalLetters': false,
      },
    );

    expect(result.text, source);
    expect(result.sourceBoundaryByNormalizedGrapheme, [0, 1, 2, 3, 4, 5]);
    expect(result.sourceEndByNormalizedGrapheme, [1, 2, 3, 4, 5]);
  });

  test('each strict override still applies its requested transformation', () {
    for (final (flag, source, expected) in [
      ('ignoreNikud', 'אָ', 'א'),
      ('ignoreTeamim', 'א֑', 'א'),
      ('ignorePunctuation', 'א!', 'א'),
      ('normalizeWhitespace', ' א  ב ', 'א ב'),
      ('normalizeFinalLetters', 'כך', 'ככ'),
    ]) {
      final result = normalize(
        source,
        PluginNormalizationProfile.strict,
        overrides: {flag: true},
      );

      expect(result.text, expected, reason: flag);
    }
  });

  test('identity boundary maps cannot be changed by callers', () {
    final result = normalize('אָ🙂', PluginNormalizationProfile.strict);

    expect(
      () => result.sourceBoundaryByNormalizedGrapheme[0] = 3,
      throwsUnsupportedError,
    );
    expect(
      () => result.sourceEndByNormalizedGrapheme.add(3),
      throwsUnsupportedError,
    );
    expect(result.sourceBoundaryByNormalizedGrapheme, [0, 1, 2]);
    expect(result.sourceEndByNormalizedGrapheme, [1, 2]);
  });

  test('display follows the current rendering flags', () {
    final visible = normalize(
      'בְּרֵאשִׁ֖ית',
      PluginNormalizationProfile.display,
    );
    final hidden = normalize(
      'בְּרֵאשִׁ֖ית',
      PluginNormalizationProfile.display,
      displayIgnoreNikud: true,
      displayIgnoreTeamim: true,
    );

    expect(visible.text, 'בְּרֵאשִׁ֖ית');
    expect(hidden.text, 'בראשית');
  });

  test('lenient removes punctuation and normalizes final letters', () {
    final result = normalize(
      'מֶלֶךְ, תָּם־סוֹף!',
      PluginNormalizationProfile.lenient,
    );

    expect(result.text, 'מלכ תמסופ');
  });

  test('overrides replace profile defaults and reject invalid values', () {
    final result = normalize(
      'אָב!',
      PluginNormalizationProfile.search,
      overrides: const {'ignorePunctuation': true},
    );
    expect(result.text, 'אב');

    expect(
      () => PluginNormalizeOptions.forProfile(
        PluginNormalizationProfile.search,
        overrides: const {'ignoreNikud': 'yes'},
      ),
      throwsFormatException,
    );
  });
}

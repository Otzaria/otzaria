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

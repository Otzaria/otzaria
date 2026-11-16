import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';

void main() {
  final cssCases = {
    'ריק': '',
    'מירכאות ויוניקוד': '@font-face{font-family:"שלום\\font";}\n</script> 😀',
    'גופנים בגודל MB': 'data:font/ttf;base64,${'A' * (2 * 1024 * 1024)}',
  };
  for (final entry in cssCases.entries) {
    test(
      'בנייה ב-isolate זהה בכל הבייטים לבונה המקורי: ${entry.key}',
      () async {
        final fontFaceJson = jsonEncode(entry.value);
        const nonceJson = '"nonce"';
        const payloadJson = '{"plugin":{"id":"test"},"theme":{"size":20}}';
        final expected = buildPluginBootScript(
          nonceJson: nonceJson,
          payloadJson: payloadJson,
          fontFaceJson: fontFaceJson,
        );
        final actual = await buildPluginBootScriptWithFonts(
          nonceJson: nonceJson,
          payloadJson: payloadJson,
          fontFaceJson: fontFaceJson,
        );
        expect(actual, expected);
      },
    );
  }
}

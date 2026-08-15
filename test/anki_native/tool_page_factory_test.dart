import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tool_page_factory.dart';

void main() {
  test('native Anki host is restricted to the official plugin on Windows', () {
    expect(
      shouldUseAnkiNativeHost('org.otzaria.anki', TargetPlatform.windows),
      isTrue,
    );
    expect(
      shouldUseAnkiNativeHost('org.otzaria.anki', TargetPlatform.linux),
      isFalse,
    );
    expect(
      shouldUseAnkiNativeHost('untrusted.plugin', TargetPlatform.windows),
      isFalse,
    );
  });
}

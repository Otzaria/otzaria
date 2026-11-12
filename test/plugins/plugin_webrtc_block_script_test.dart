import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_webrtc_block_script.dart';

void main() {
  group('buildPluginWebRtcBlockScript', () {
    test('מוזרק לפני קוד הדף וגם ל-iframes', () {
      final script = buildPluginWebRtcBlockScript();
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.forMainFrameOnly, isFalse);
    });
  });
}

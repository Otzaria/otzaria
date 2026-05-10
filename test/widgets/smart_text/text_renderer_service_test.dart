import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

void main() {
  group('TextRendererService', () {
    test('removes subtitle headings when showSubtitles is false', () {
      final processed = TextRendererService.processText(
        '<h1>ספר</h1>\n<h2>פרק א</h2>\nתוכן',
        const RenderSettings(showSubtitles: false),
      );

      expect(processed, contains('<h1>ספר</h1>'));
      expect(processed, isNot(contains('<h2>פרק א</h2>')));
      expect(processed, contains('תוכן'));
    });
  });
}

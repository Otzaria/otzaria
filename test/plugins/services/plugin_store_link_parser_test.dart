import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';

void main() {
  group('PluginStoreLinkParser', () {
    test('parses valid plugin install links', () {
      final request = PluginStoreLinkParser.parseUri(
        Uri.parse(
          'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fplugin.otzplugin',
        ),
      );

      expect(request, isNotNull);
      expect(
        request!.downloadUri.toString(),
        'https://example.com/plugin.otzplugin',
      );
      expect(request.forceOverwrite, isFalse);
    });

    test('parses overwrite flag from install links', () {
      final request = PluginStoreLinkParser.parseUri(
        Uri.parse(
          'otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fplugin.otzplugin&overwrite=true',
        ),
      );

      expect(request, isNotNull);
      expect(request!.forceOverwrite, isTrue);
    });

    test('keeps a same-origin callback context', () {
      final request = PluginStoreLinkParser.parseUri(
        Uri.parse(
          'otzaria://plugin/install?url=https%3A%2F%2Fstore.example.com%2Fplugin.otzplugin&token=one-time&callback=https%3A%2F%2Fstore.example.com%2Fapi%2Finstall-result',
        ),
      );

      expect(request?.reportContext?.token, 'one-time');
      expect(
        request?.reportContext?.callbackUrl.toString(),
        'https://store.example.com/api/install-result',
      );
    });

    test('drops a callback from a different origin', () {
      final request = PluginStoreLinkParser.parseUri(
        Uri.parse(
          'otzaria://plugin/install?url=https%3A%2F%2Fstore.example.com%2Fplugin.otzplugin&token=one-time&callback=https%3A%2F%2Fevil.example.com%2Fcollect',
        ),
      );

      expect(request, isNotNull);
      expect(request!.reportContext, isNull);
    });

    test('rejects links without download url', () {
      final request = PluginStoreLinkParser.parseUri(
        Uri.parse('otzaria://plugin/install'),
      );

      expect(request, isNull);
    });

    test('rejects non-http download links', () {
      final request = PluginStoreLinkParser.parseUri(
        Uri.parse(
          'otzaria://plugin/install?url=file%3A%2F%2FC%3A%2Ftemp%2Fplugin.otzplugin',
        ),
      );

      expect(request, isNull);
    });

    test('rejects unrelated otzaria links', () {
      final request = PluginStoreLinkParser.parseUri(
        Uri.parse('otzaria://note?id=123'),
      );

      expect(request, isNull);
    });
  });
}

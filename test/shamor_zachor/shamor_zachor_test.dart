import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';

void main() {
  group('ShamorZachror Package Tests', () {
    test('ShamorZachorWidget should be instantiable', () {
      const widget = ShamorZachorWidget();
      expect(widget, isNotNull);
      expect(widget.config, equals(ShamorZachorConfig.defaultConfig));
    });

    test('ShamorZachorConfig should have default values', () {
      const config = ShamorZachorConfig.defaultConfig;
      expect(config.assetsBasePath, isNull);
      expect(config.themeData, isNull);
      expect(config.textDirection, isNull);
      expect(config.locale, isNull);
    });

    test('ShamorZachorConfig should accept custom values', () {
      const config = ShamorZachorConfig(
        assetsBasePath: 'custom/path',
      );
      expect(config.assetsBasePath, equals('custom/path'));
    });
  });
}

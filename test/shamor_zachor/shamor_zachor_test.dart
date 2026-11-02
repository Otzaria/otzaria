import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';

void main() {
  group('ShamorZachror Package Tests', () {
    test('ShamorZachorWidget should be instantiable', () {
      const widget = ShamorZachorWidget();
      expect(widget, isNotNull);
    });
  });
}

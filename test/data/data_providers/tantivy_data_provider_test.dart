import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';

void main() {
  group('TantivyDataProvider.shouldPromptForManualReindex', () {
    test('מחזיר false כשאין אינדקס קיים גם אם האינדקס אינו תואם', () {
      final shouldPrompt = TantivyDataProvider.shouldPromptForManualReindex(
        indexExistedBeforeInit: false,
        indexCompatible: false,
      );

      expect(shouldPrompt, isFalse);
    });

    test('מחזיר true כשיש אינדקס קיים שאינו תואם לגרסת המנוע', () {
      final shouldPrompt = TantivyDataProvider.shouldPromptForManualReindex(
        indexExistedBeforeInit: true,
        indexCompatible: false,
      );

      expect(shouldPrompt, isTrue);
    });

    test('מחזיר false כשיש אינדקס קיים שתואם לגרסת המנוע', () {
      final shouldPrompt = TantivyDataProvider.shouldPromptForManualReindex(
        indexExistedBeforeInit: true,
        indexCompatible: true,
      );

      expect(shouldPrompt, isFalse);
    });
  });
}

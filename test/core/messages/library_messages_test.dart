import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';

void main() {
  group('LibraryMessages.searchIndexOpenFailed', () {
    test('כולל את נתיב האינדקס שנכשל', () {
      final message = LibraryMessages.searchIndexOpenFailed(
        r'F:\Otzaria\index',
      );

      expect(message, contains(r'F:\Otzaria\index'));
      expect(message, contains('הגדרות הספרייה'));
    });

    test('בלי נתיב ההודעה עדיין תקינה', () {
      for (final message in [
        LibraryMessages.searchIndexOpenFailed(),
        LibraryMessages.searchIndexOpenFailed(''),
      ]) {
        expect(message, startsWith('פתיחת אינדקס החיפוש נכשלה'));
        expect(message, isNot(contains('()')));
      }
    });
  });
}

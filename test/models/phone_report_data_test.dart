import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/phone_report_data.dart';

void main() {
  group('ErrorType', () {
    test('should have all expected error types', () {
      expect(ErrorType.errorTypes.length, equals(6));
      expect(ErrorType.errorTypes[0].hebrewLabel, equals('שגיאת כתיב'));
      expect(ErrorType.errorTypes[5].hebrewLabel, equals('אחר'));
    });
  });
}

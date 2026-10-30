import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('עלייה (#3669): סריקת temp לגיבוי יתום רק כש-seforim.db חסר', () {
    final source = File(
      'lib/main.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final start = source.indexOf(
      'Future<void> _recoverOrphanedDbBackup() async {',
    );
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, source.indexOf('\n}\n', start));
    expect(body, contains('onlyIfDbMissing: true'));
  });
}

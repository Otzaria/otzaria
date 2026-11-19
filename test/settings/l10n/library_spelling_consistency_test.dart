import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_catalogs.g.dart';

void main() {
  for (final (word, issue) in [('ספריה', 1189), ('כרטיסיה', 4201)]) {
    test('אין מחרוזות ממשק עם הכתיב "$word" (issue #$issue)', () {
      final singleYod = kSettingsCatalogs['en']!.keys
          .where((key) => key.contains(word))
          .toList();
      expect(singleYod, isEmpty, reason: 'מפתחות בכתיב חסר: $singleYod');
    });
  }
}

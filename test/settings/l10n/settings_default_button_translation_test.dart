import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_catalogs.g.dart';

/// issue #1319 — הכפתור "השתמש בברירת מחדל" הופיע באנגלית כ-"Use the Lefault".
void main() {
  test('"השתמש בברירת מחדל" מתורגם ל-"Use the Default"', () {
    expect(kSettingsCatalogs['en']!['השתמש בברירת מחדל'], 'Use the Default');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/search/settings_search_index.g.dart';
import 'package:otzaria/settings/view/settings_screen.dart';

void main() {
  test('חיפוש כרטיס SD מפנה לכרטיס מיקום אחסון הספרייה', () {
    final entry = kGeneratedSettingsSearchEntries.singleWhere(
      (entry) => entry.id == 'library.android_storage',
    );

    expect(entry.tab, SettingsTab.library);
    expect(entry.cardId, 'library.android_storage');
    expect(entry.matchScore('כרטיס זיכרון'), greaterThan(0));
  });
}

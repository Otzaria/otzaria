import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/system_font_locator_io.dart';

void main() {
  test('ב-iOS הסריקה היחידה היא תיקיית הגופנים של המשתמש בארגז החול', () {
    const home = '/var/mobile/Containers/Data/Application/ABC';
    expect(fontDirectoriesFor('ios', {'HOME': home}), [
      '$home/Library/Application Support/otzaria_user_fonts',
    ]);
    expect(
      userFontsDirectoryFor('ios', {'HOME': home}),
      '$home/Library/Application Support/otzaria_user_fonts',
    );
  });

  test('בפלטפורמות אחרות אין תיקיית משתמש (ייבוא גופן הוא ל-iOS)', () {
    for (final os in ['windows', 'macos', 'linux', 'android']) {
      expect(userFontsDirectoryFor(os, {'HOME': '/h'}), isNull, reason: os);
    }
  });

  test('בלי HOME אין תיקייה, והסריקה לא מקבלת נתיב "null/..."', () {
    expect(userFontsDirectoryFor('ios', const {}), isNull);
    expect(fontDirectoriesFor('ios', const {}), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/system_font_locator_io.dart';

void main() {
  group('תיקיות גופנים בלינוקס', () {
    test('נסרקות גם ~/.fonts ו-\$XDG_DATA_HOME/fonts', () {
      final withXdg = fontDirectoriesFor('linux', {
        'HOME': '/home/u',
        'XDG_DATA_HOME': '/data/u',
      });
      expect(
        withXdg,
        containsAll([
          '/usr/share/fonts',
          '/usr/local/share/fonts',
          '/data/u/fonts',
          '/home/u/.fonts',
        ]),
      );
    });

    test('בלי XDG_DATA_HOME ברירת המחדל היא ~/.local/share/fonts', () {
      final dirs = fontDirectoriesFor('linux', {'HOME': '/home/u'});
      expect(dirs, contains('/home/u/.local/share/fonts'));
      expect(dirs, contains('/home/u/.fonts'));
      expect(dirs.where((d) => d.contains('XDG')), isEmpty);
    });

    test('XDG_DATA_HOME ריק נחשב כלא מוגדר', () {
      final dirs = fontDirectoriesFor('linux', {
        'HOME': '/home/u',
        'XDG_DATA_HOME': '',
      });
      expect(dirs, contains('/home/u/.local/share/fonts'));
    });

    test('macOS ו-Windows לא השתנו', () {
      expect(fontDirectoriesFor('macos', {'HOME': '/Users/u'}), [
        '/Library/Fonts',
        '/System/Library/Fonts',
        '/Users/u/Library/Fonts',
      ]);
      expect(
        fontDirectoriesFor('windows', {
          'windir': r'C:\Windows',
          'USERPROFILE': r'C:\Users\u',
        }),
        [
          r'C:\Windows\Fonts',
          r'C:\Users\u\AppData\Local\Microsoft\Windows\Fonts',
        ],
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_protocol_registration_service.dart';

void main() {
  group('PluginProtocolRegistrationService', () {
    test('resolveWindowsRegistryExecutable prefers WINDIR', () {
      final executable =
          PluginProtocolRegistrationService.resolveWindowsRegistryExecutable({
            'WINDIR': r'D:\Windows',
            'SystemRoot': r'C:\Windows',
          });

      expect(executable, r'D:\Windows\System32\reg.exe');
    });

    test(
      'buildWindowsRegistrationCommands uses executable for icon and open command',
      () {
        final commands =
            PluginProtocolRegistrationService.buildWindowsRegistrationCommands(
              r'C:\Program Files\Otzaria\otzaria.exe',
            );

        expect(commands.length, greaterThanOrEqualTo(4));
        expect(commands[2], [
          'add',
          r'HKCU\Software\Classes\otzaria\DefaultIcon',
          '/ve',
          '/d',
          r'C:\Program Files\Otzaria\otzaria.exe',
          '/f',
        ]);
        expect(commands[3], [
          'add',
          r'HKCU\Software\Classes\otzaria\shell\open\command',
          '/ve',
          '/d',
          r'"C:\Program Files\Otzaria\otzaria.exe" "%1"',
          '/f',
        ]);
      },
    );

    test('buildWindowsRegistrationCommands כולל שיוך קובץ .otzplugin', () {
      final commands =
          PluginProtocolRegistrationService.buildWindowsRegistrationCommands(
            r'C:\Program Files\Otzaria\otzaria.exe',
          );

      // ProgID open command — `reg add` שפותח את אוצריא כשמשתמש פותח קובץ ‎.otzplugin
      expect(
        commands.any(
          (cmd) =>
              cmd.length >= 6 &&
              cmd[0] == 'add' &&
              cmd[1] ==
                  r'HKCU\Software\Classes\OtzariaPluginFile\shell\open\command' &&
              cmd[4] == r'"C:\Program Files\Otzaria\otzaria.exe" "%1"',
        ),
        isTrue,
        reason: 'חסר הרישום של פקודת open עבור ProgID של ‎.otzplugin',
      );

      // DefaultIcon מצביע על משאב ‎1 ב-EXE (האייקון הייעודי לתוסף)
      expect(
        commands.any(
          (cmd) =>
              cmd.length >= 6 &&
              cmd[0] == 'add' &&
              cmd[1] ==
                  r'HKCU\Software\Classes\OtzariaPluginFile\DefaultIcon' &&
              cmd[4] == r'C:\Program Files\Otzaria\otzaria.exe,1',
        ),
        isTrue,
        reason: 'DefaultIcon חייב להצביע על משאב ‎1 ב-EXE',
      );

      // Extension → ProgID
      expect(
        commands.any(
          (cmd) =>
              cmd.length >= 6 &&
              cmd[0] == 'add' &&
              cmd[1] == r'HKCU\Software\Classes\.otzplugin' &&
              cmd[2] == '/ve' &&
              cmd[4] == 'OtzariaPluginFile',
        ),
        isTrue,
        reason: 'חסר הקישור בין סיומת ‎.otzplugin ל-ProgID',
      );

      // EditFlags=FTA_NoRecentDocs — מונע הוספת ‎.otzplugin ל-Jump List
      expect(
        commands.any(
          (cmd) =>
              cmd.length >= 9 &&
              cmd[0] == 'add' &&
              cmd[1] == r'HKCU\Software\Classes\OtzariaPluginFile' &&
              cmd[2] == '/v' &&
              cmd[3] == 'EditFlags' &&
              cmd[5] == 'REG_DWORD' &&
              cmd[7] == '0x00100000',
        ),
        isTrue,
        reason: 'חסר דגל FTA_NoRecentDocs שמונע כניסה ל"מסמכים אחרונים"',
      );
    });

    test('buildLinuxDesktopEntry does not add leading or empty lines', () {
      final entry = PluginProtocolRegistrationService.buildLinuxDesktopEntry(
        executable: '/opt/otzaria/otzaria',
        scheme: 'otzaria',
      );

      final lines = entry.split('\n');
      expect(lines.first, '[Desktop Entry]');
      expect(
        lines.where((line) => line.trim().isEmpty).length,
        1,
      );
      expect(lines[lines.length - 2], 'StartupNotify=true');
    });

    test('buildLinuxDesktopEntry includes icon only when provided', () {
      final entry = PluginProtocolRegistrationService.buildLinuxDesktopEntry(
        executable: '/opt/otzaria/otzaria',
        scheme: 'otzaria',
        iconPath: '/opt/otzaria/icon.png',
      );

      expect(entry, contains('Icon=/opt/otzaria/icon.png'));
      expect(
        entry.split('\n').where((line) => line.trim().isEmpty).length,
        1,
      );
    });

    test('buildLinuxDesktopEntry מוסיף MIME type של תוסף כשמסופק', () {
      final entry = PluginProtocolRegistrationService.buildLinuxDesktopEntry(
        executable: '/opt/otzaria/otzaria',
        scheme: 'otzaria',
        pluginMimeType: 'application/x-otzaria-plugin',
      );

      expect(
        entry,
        contains(
          'MimeType=x-scheme-handler/otzaria;application/x-otzaria-plugin;',
        ),
      );
    });

    test('buildLinuxMimeXml מייצר תיאור MIME עם glob תקין', () {
      final xml = PluginProtocolRegistrationService.buildLinuxMimeXml(
        mimeType: 'application/x-otzaria-plugin',
        extension: '.otzplugin',
      );

      expect(xml, contains('type="application/x-otzaria-plugin"'));
      expect(xml, contains('<glob pattern="*.otzplugin"/>'));
      expect(xml, isNot(contains('<icon')));
    });

    test('buildLinuxMimeXml משבץ שם אייקון כשמסופק', () {
      final xml = PluginProtocolRegistrationService.buildLinuxMimeXml(
        mimeType: 'application/x-otzaria-plugin',
        extension: '.otzplugin',
        iconName: 'application-x-otzaria-plugin',
      );

      expect(xml, contains('<icon name="application-x-otzaria-plugin"/>'));
    });
  });
}

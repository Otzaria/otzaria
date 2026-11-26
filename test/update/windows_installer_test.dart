import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/windows_installer.dart';
import 'package:otzaria/update/windows_installer_args.dart'
    show windowsCommandLine;

void main() {
  group('perUserSilentInstallerArguments', () {
    test('silent install for the current user, relaunches the app', () {
      expect(
        perUserSilentInstallerArguments(relaunchApp: true),
        '/SILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER',
      );
    });

    test('adds /NOLAUNCH=1 when the app must not reopen', () {
      expect(
        perUserSilentInstallerArguments(relaunchApp: false),
        '/SILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /NOLAUNCH=1',
      );
    });
  });

  group('installModeSwitchArguments', () {
    // הערכים שהמתקין משווה אליהם ב-SwitchModeTarget (installer/otzaria.iss).
    test('all users', () {
      expect(installModeSwitchArguments(WindowsInstallScope.allUsers), [
        '/SWITCHMODE=allusers',
      ]);
    });

    test('current user only', () {
      expect(installModeSwitchArguments(WindowsInstallScope.currentUser), [
        '/SWITCHMODE=currentuser',
      ]);
    });

    test('a single argument the installer reads as one parameter', () {
      // CreateProcessW מקבל כל ארגומנט בגרשיים; Inno מסיר אותם ב-ParamStr.
      expect(
        windowsCommandLine(
          r'C:\Temp\otzaria-1.0.0.exe',
          installModeSwitchArguments(WindowsInstallScope.allUsers),
        ),
        r'"C:\Temp\otzaria-1.0.0.exe" "/SWITCHMODE=allusers"',
      );
    });
  });
}

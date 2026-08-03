import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/windows_installer.dart';

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
}

import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_release_version.dart';
import 'my_update_widget.dart' show downloadInstallerForModeSwitch;
import 'windows_installer.dart';

export 'windows_installer.dart' show WindowsInstallScope;

/// העברת התקנת Windows בין "רק בשבילי" ל"כל המשתמשים": המתקין המלא רץ עם
/// [installModeSwitchArguments], ומסיר בסיום את ההתקנה בהיקף הקודם.
class InstallModeSwitcher {
  InstallModeSwitcher({
    required this.currentScope,
    Future<File> Function()? downloadInstaller,
    bool Function(String installerPath, List<String> arguments)? launch,
    Future<void> Function()? keepDataPaths,
  }) : _downloadInstaller = downloadInstaller ?? _downloadForRunningVersion,
       _launch = launch ?? _launchDetached,
       _keepDataPaths = keepDataPaths ?? (() async {});

  /// `null` מחוץ ל-Windows ובעותק נייד, שאין לו רישום במערכת.
  static InstallModeSwitcher? forCurrentProcess() {
    if (!Platform.isWindows || AppPaths.isPortable) return null;
    return InstallModeSwitcher(
      currentScope: AppPaths.isWindowsSystemInstall
          ? WindowsInstallScope.allUsers
          : WindowsInstallScope.currentUser,
      keepDataPaths: _pinIndexPath,
    );
  }

  final WindowsInstallScope currentScope;
  final Future<File> Function() _downloadInstaller;
  final bool Function(String, List<String>) _launch;
  final Future<void> Function() _keepDataPaths;

  WindowsInstallScope get otherScope =>
      currentScope == WindowsInstallScope.allUsers
      ? WindowsInstallScope.currentUser
      : WindowsInstallScope.allUsers;

  /// מוריד ומשגר את המתקין, ואם הוא רץ — סוגר את אוצריא ב-[quit] כדי שיוכל
  /// להחליף את קבציה. `false` = לא שוגר, ואוצריא נשארת פתוחה.
  Future<bool> switchTo(
    WindowsInstallScope target, {
    required Future<void> Function() quit,
  }) async {
    final installer = await _downloadInstaller();
    await _keepDataPaths();
    if (!_launch(installer.absolute.path, installModeSwitchArguments(target))) {
      return false;
    }
    await quit();
    return true;
  }

  // נתיב האינדקס שאינו שמור נגזר מהיקף ההתקנה (ProgramData מול AppData, ותיקיית
  // index ריקה שהמתקין יוצר) — בלי קיבוע ההתקנה החדשה הייתה בונה אינדקס מחדש.
  static Future<void> _pinIndexPath() async {
    if ((Settings.getValue<String>(SettingsRepository.keyIndexPath) ?? '')
        .isNotEmpty) {
      return;
    }
    await Settings.setValue<String>(
      SettingsRepository.keyIndexPath,
      await AppPaths.getIndexPath(),
    );
  }

  static Future<File> _downloadForRunningVersion() async =>
      downloadInstallerForModeSwitch(
        appReleaseVersion(await PackageInfo.fromPlatform()),
      );

  // מנותק מה-Job של אוצריא, כמו מתקין העדכון, כדי לשרוד את סגירתה.
  static bool _launchDetached(String path, List<String> arguments) =>
      launchWindowsDetachedProcess(path, arguments: arguments);
}

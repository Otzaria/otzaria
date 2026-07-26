import 'windows_installer_stub.dart'
    if (dart.library.io) 'windows_installer_io.dart'
    as impl;

export 'windows_installer_args.dart' show perUserSilentInstallerArguments;

/// משגר את מתקין העדכון של Windows כך שישרוד את סגירת אוצריא.
/// מחזיר true אם היצירה הצליחה; בפלטפורמות ללא dart:io תמיד false.
bool launchWindowsSilentInstaller({
  required String installerPath,
  required bool relaunchApp,
}) => impl.launchWindowsSilentInstaller(
  installerPath: installerPath,
  relaunchApp: relaunchApp,
);

/// משגר את המתקין של Windows. אינו נתמך מחוץ ל-Windows.
bool launchWindowsSilentInstaller({
  required String installerPath,
  required bool relaunchApp,
}) => false;

/// משגר קובץ הרצה של Windows. אינו נתמך מחוץ ל-Windows.
bool launchWindowsDetachedProcess(String executablePath) => false;

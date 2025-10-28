import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:updat/updat.dart';
import 'package:updat/updat_window_manager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'hebrew_updat_widgets.dart';

/// סוג ההתקנה המוגדר בזמן build (אופציונלי)
/// להגדרה: --dart-define=INSTALL_KIND=msix/exe/zip
const _kInstallKind =
    String.fromEnvironment('INSTALL_KIND', defaultValue: 'auto');

/// זיהוי סוג ההתקנה ב-Windows
/// אם הוגדר INSTALL_KIND בזמן build - משתמש בו
/// אחרת - מזהה לפי נתיב הקובץ
String _preferredWindowsFormat() {
  if (!Platform.isWindows) return 'unknown';

  // אם הוגדר סוג התקנה בזמן build - משתמש בו
  if (_kInstallKind != 'auto') return _kInstallKind; // 'msix' | 'exe' | 'zip'

  try {
    // זיהוי אוטומטי לפי נתיב הקובץ
    final executablePath = Platform.resolvedExecutable.toLowerCase();

    if (executablePath.contains('\\windowsapps\\')) {
      return 'msix'; // התקנת MSIX
    }

    if (executablePath.contains('\\program files\\') ||
        executablePath.contains('\\program files (x86)\\')) {
      return 'exe'; // התקנה תקנית
    }

    return 'zip'; // גרסה ניידת/ידנית
  } catch (e) {
    // במקרה של שגיאה, ברירת מחדל היא EXE
    return 'exe';
  }
}

/// עוטף את [hebrewFlatChip] ומבטל אוטומטית שגיאות עדכון לאחר השהיה קצרה.
Widget _hebrewFlatChipAutoHideError({
  required BuildContext context,
  required String? latestVersion,
  required String appVersion,
  required UpdatStatus status,
  required void Function() checkForUpdate,
  required void Function() openDialog,
  required void Function() startUpdate,
  required Future<void> Function() launchInstaller,
  required void Function() dismissUpdate,
}) {
  if (status == UpdatStatus.error) {
    Future.delayed(const Duration(seconds: 3), dismissUpdate);
  }
  return hebrewFlatChip(
    context: context,
    latestVersion: latestVersion,
    appVersion: appVersion,
    status: status,
    checkForUpdate: checkForUpdate,
    openDialog: openDialog,
    startUpdate: startUpdate,
    launchInstaller: launchInstaller,
    dismissUpdate: dismissUpdate,
  );
}

class MyUpdatWidget extends StatelessWidget {
  const MyUpdatWidget({super.key, required this.child});

  final Widget child;
  @override
  Widget build(BuildContext context) {
    // Don't show update widget in debug mode
    if (kDebugMode) {
      return child;
    }

    return FutureBuilder(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return child;
          }
          return UpdatWindowManager(
            getLatestVersion: () async {
              // Github gives us a super useful latest endpoint, and we can use it to get the latest stable release
              final isDevChannel =
                  Settings.getValue<bool>('key-dev-channel') ?? false;

              String normalizeVersion(String version) {
                // Remove 'v' prefix if present
                version =
                    version.startsWith('v') ? version.substring(1) : version;
                // Remove build number (everything after '+')
                final plusIndex = version.indexOf('+');
                if (plusIndex != -1) {
                  version = version.substring(0, plusIndex);
                }
                return version;
              }

              if (isDevChannel) {
                // For dev channel, get the latest pre-release from the main repo
                final data = await http.get(Uri.parse(
                  "https://api.github.com/repos/Y-PLONI/otzaria/releases",
                ));
                final releases = jsonDecode(data.body) as List;
                // Find the first pre-release that is not a draft and not a PR preview
                final preRelease = releases.firstWhere(
                  (release) =>
                      release["prerelease"] == true &&
                      release["draft"] == false &&
                      !release["tag_name"].toString().contains('-pr'),
                  orElse: () => releases.first,
                );
                return normalizeVersion(preRelease["tag_name"]);
              } else {
                // For stable channel, get the latest stable release
                final data = await http.get(Uri.parse(
                  "https://api.github.com/repos/sivan22/otzaria/releases/latest",
                ));
                return normalizeVersion(jsonDecode(data.body)["tag_name"]);
              }
            },
            getBinaryUrl: (version) async {
              final isDev = Settings.getValue<bool>('key-dev-channel') ?? false;
              final repo = isDev ? "Y-PLONI" : "sivan22";

              // קבלת פרטי ה-release
              dynamic release;
              if (isDev) {
                // ערוץ dev - חיפוש לפי התחלת גרסה
                final data = await http.get(Uri.parse(
                    "https://api.github.com/repos/$repo/otzaria/releases"));
                final releases = jsonDecode(data.body) as List;
                final versionStr = version ?? '';
                release = releases.firstWhere(
                  (r) => r["tag_name"].toString().startsWith(versionStr),
                  orElse: () => releases.first,
                );
              } else {
                // ערוץ stable - ניסיון עם/בלי קידומת v
                var resp = await http.get(Uri.parse(
                    "https://api.github.com/repos/$repo/otzaria/releases/tags/$version"));
                if (resp.statusCode == 404) {
                  resp = await http.get(Uri.parse(
                      "https://api.github.com/repos/$repo/otzaria/releases/tags/v$version"));
                }
                release = jsonDecode(resp.body);
              }

              final assets =
                  (release["assets"] as List).cast<Map<String, dynamic>>();
              final platform = Platform.operatingSystem.toLowerCase();

              String? assetUrl;

              // פונקציה לבחירת קובץ Windows לפי סדר עדיפות
              String? pickWindows(List<String> extsInOrder) {
                String? foundZip;
                for (final a in assets) {
                  final name = (a["name"] as String).toLowerCase();
                  final url = a["browser_download_url"] as String;
                  final isWin = name.contains('win') ||
                      name.contains('windows') ||
                      name.endsWith('.exe') ||
                      name.endsWith('.msix') ||
                      name.endsWith('.msixbundle') ||
                      name.endsWith('.appinstaller');
                  if (!isWin) continue;

                  for (final ext in extsInOrder) {
                    if (name.endsWith(ext)) return url;
                  }
                  if (name.endsWith('.zip') && foundZip == null) foundZip = url;
                }
                return foundZip;
              }

              if (platform == 'windows') {
                // בחירת סדר עדיפות לפי סוג ההתקנה
                final pref = _preferredWindowsFormat();
                final order = switch (pref) {
                  'msix' => [
                      '.msixbundle',
                      '.msix',
                      '.appinstaller',
                      '.exe',
                      '.zip'
                    ],
                  'exe' => [
                      '.exe',
                      '.msixbundle',
                      '.msix',
                      '.appinstaller',
                      '.zip'
                    ],
                  'zip' => [
                      '.zip',
                      '.exe',
                      '.msixbundle',
                      '.msix',
                      '.appinstaller'
                    ],
                  _ => [
                      '.exe',
                      '.msixbundle',
                      '.msix',
                      '.appinstaller',
                      '.zip'
                    ],
                };
                assetUrl = pickWindows(order);
              } else if (platform == 'macos') {
                // macOS - חיפוש קובץ zip
                for (final a in assets) {
                  final n = (a["name"] as String).toLowerCase();
                  if ((n.contains('macos') ||
                          n.contains('darwin') ||
                          n.contains('mac')) &&
                      n.endsWith('.zip')) {
                    assetUrl = a["browser_download_url"] as String;
                    break;
                  }
                }
              } else if (platform == 'linux') {
                // Linux - עדיפות: DEB -> RPM -> ZIP
                for (final a in assets) {
                  final n = (a["name"] as String).toLowerCase();
                  final u = a["browser_download_url"] as String;
                  if (n.endsWith('.deb')) {
                    assetUrl = u;
                    break;
                  }
                }
                if (assetUrl == null) {
                  for (final a in assets) {
                    final n = (a["name"] as String).toLowerCase();
                    final u = a["browser_download_url"] as String;
                    if (n.endsWith('.rpm')) {
                      assetUrl = u;
                      break;
                    }
                  }
                }
                if (assetUrl == null) {
                  for (final a in assets) {
                    final n = (a["name"] as String).toLowerCase();
                    final u = a["browser_download_url"] as String;
                    if ((n.contains('linux') || n.contains('gnu')) &&
                        n.endsWith('.zip')) {
                      assetUrl = u;
                      break;
                    }
                  }
                }
              }

              if (assetUrl == null) {
                throw Exception('No suitable binary found for $platform');
              }
              return assetUrl;
            },
            appName: "otzaria", // This is used to name the downloaded files.
            getChangelog: (_, __) async {
              // Load changelog directly from GitHub repository
              try {
                final response = await http.get(
                  Uri.parse('https://raw.githubusercontent.com/Y-PLONI/otzaria/refs/heads/dev/assets/%D7%99%D7%95%D7%9E%D7%9F%20%D7%A9%D7%99%D7%A0%D7%95%D7%99%D7%99%D7%9D.md'),
                ).timeout(const Duration(seconds: 10));

                if (response.statusCode == 200) {
                  return response.body;
                } else {
                  return 'שגיאה בטעינת יומן השינויים.\nקוד שגיאה: ${response.statusCode}';
                }
              } catch (e) {
                return 'שגיאה בטעינת יומן השינויים: $e';
              }
            },
            currentVersion: snapshot.data!.version,
            updateChipBuilder: _hebrewFlatChipAutoHideError,
            updateDialogBuilder: hebrewDefaultDialog,

            callback: (status) {},
            child: child,
          );
        });
  }
}

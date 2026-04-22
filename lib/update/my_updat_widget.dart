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
import 'linux_installer.dart';
import 'package:otzaria/settings/settings_exports.dart';

const _changelogUrl =
    'https://raw.githubusercontent.com/Otzaria/otzaria/refs/heads/migrationDB_V2/assets/%D7%99%D7%95%D7%9E%D7%9F%20%D7%A9%D7%99%D7%A0%D7%95%D7%99%D7%99%D7%9D.md';
const _githubOwner = 'Otzaria';
const _githubRepository = 'otzaria';

final _changelogHeadingPattern = RegExp(
  r'^\s*(?:(?:#{1,6}|[*-])\s*)?\*{0,2}v?(\d+(?:\.\d+){1,2}(?:[-+][^\s*]+)?)\*{0,2}\s*$',
);

class _ParsedVersion implements Comparable<_ParsedVersion> {
  final int major;
  final int minor;
  final int patch;

  const _ParsedVersion(this.major, this.minor, this.patch);

  @override
  int compareTo(_ParsedVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) return majorCompare;

    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) return minorCompare;

    return patch.compareTo(other.patch);
  }

  bool operator >(_ParsedVersion other) => compareTo(other) > 0;

  bool operator <=(_ParsedVersion other) => compareTo(other) <= 0;

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ParsedVersion &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}

String _normalizeVersion(String version) {
  var normalized = version.trim();
  if (normalized.startsWith('v')) {
    normalized = normalized.substring(1);
  }

  final plusIndex = normalized.indexOf('+');
  if (plusIndex != -1) {
    normalized = normalized.substring(0, plusIndex);
  }

  return normalized;
}

_ParsedVersion? _tryParseVersion(String version) {
  final core = _normalizeVersion(version).split('-').first;
  final parts = core.split('.');
  if (parts.length < 2 || parts.length > 3) return null;

  final major = int.tryParse(parts[0]);
  final minor = int.tryParse(parts[1]);
  final patch = parts.length == 3 ? int.tryParse(parts[2]) : 0;
  if (major == null || minor == null || patch == null) return null;

  return _ParsedVersion(major, minor, patch);
}

/// מחזירה את פריטי יומן השינויים שבין הגרסה הנוכחית לגרסה הזמינה.
@visibleForTesting
String changelogBetweenVersionsForUpdateDialog({
  required String changelog,
  required String currentVersion,
  required String latestVersion,
}) {
  final current = _tryParseVersion(currentVersion);
  final latest = _tryParseVersion(latestVersion);
  if (current == null || latest == null || latest <= current) {
    return changelog;
  }

  final lines = changelog.split('\n');
  final selected = <String>[];
  var includeCurrentSection = false;
  var sawVersionHeading = false;

  for (final line in lines) {
    final match = _changelogHeadingPattern.firstMatch(line);
    if (match != null) {
      sawVersionHeading = true;
      final headingVersion = _tryParseVersion(match.group(1)!);
      includeCurrentSection = headingVersion != null &&
          headingVersion > current &&
          headingVersion <= latest;

      if (includeCurrentSection) {
        if (selected.isNotEmpty && selected.last.trim().isNotEmpty) {
          selected.add('');
        }
        selected.add(line);
      }
      continue;
    }

    if (!sawVersionHeading) {
      continue;
    }

    if (includeCurrentSection) {
      selected.add(line);
    }
  }

  final result = selected.join('\n').trim();
  if (result.isEmpty) {
    return 'לא נמצאו פריטי יומן שינויים בין גרסה $currentVersion לגרסה $latestVersion.';
  }
  return result;
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

  // Wrap launchInstaller for Linux
  final wrappedLaunchInstaller = wrapLinuxInstaller(launchInstaller, 'otzaria');

  return hebrewFlatChip(
    context: context,
    latestVersion: latestVersion,
    appVersion: appVersion,
    status: status,
    checkForUpdate: checkForUpdate,
    openDialog: openDialog,
    startUpdate: startUpdate,
    launchInstaller: wrappedLaunchInstaller,
    dismissUpdate: dismissUpdate,
  );
}

class MyUpdatWidget extends StatelessWidget {
  const MyUpdatWidget({super.key, required this.child});

  final Widget child;
  @override
  Widget build(BuildContext context) {
    // Don't show update widget in debug mode or offline mode
    final isOfflineMode =
        Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;
    final softwareAndBookUpdatesEnabled = Settings.getValue<bool>(
          SettingsRepository.keySoftwareAndBookUpdatesEnabled,
          defaultValue: true,
        ) ??
        true;
    if (kDebugMode || isOfflineMode || !softwareAndBookUpdatesEnabled) {
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

              if (isDevChannel) {
                // For dev channel, get the latest pre-release from the main repo
                final data = await http.get(Uri.parse(
                  "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases",
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
                return _normalizeVersion(preRelease["tag_name"]);
              } else {
                // For stable channel, get the latest stable release
                final data = await http.get(Uri.parse(
                  "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/latest",
                ));
                return _normalizeVersion(jsonDecode(data.body)["tag_name"]);
              }
            },
            getBinaryUrl: (version) async {
              final isDev = Settings.getValue<bool>('key-dev-channel') ?? false;

              // קבלת פרטי ה-release
              dynamic release;
              if (isDev) {
                // ערוץ dev - חיפוש לפי התחלת גרסה
                final data = await http.get(Uri.parse(
                    "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases"));
                final releases = jsonDecode(data.body) as List;
                final versionStr = version ?? '';
                release = releases.firstWhere(
                  (r) => r["tag_name"].toString().startsWith(versionStr),
                  orElse: () => releases.first,
                );
              } else {
                // ערוץ stable - ניסיון עם/בלי קידומת v
                var resp = await http.get(Uri.parse(
                    "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/tags/$version"));
                if (resp.statusCode == 404) {
                  resp = await http.get(Uri.parse(
                      "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/tags/v$version"));
                }
                // וידוא שה-release נמצא
                if (resp.statusCode >= 400) {
                  throw Exception(
                      'Release "$version" not found (status ${resp.statusCode})');
                }
                release = jsonDecode(resp.body);
              }

              final assets =
                  (release["assets"] as List).cast<Map<String, dynamic>>();
              final platform = Platform.operatingSystem.toLowerCase();

              String? assetUrl;

              // בחירת קובץ Windows לפי סדר עדיפות:
              // 1. קובץ -update.exe (קטן, ללא DLLים — לעדכון בלבד)
              // 2. קובץ .exe רגיל (לא full, לא update)
              // 3. fallback ל-ZIP
              // קבצי -full.exe מדולגים תמיד (מכילים ספרייה מלאה)
              String? pickWindows({bool allowZipFallback = true}) {
                String? regularExe;
                String? foundZip;
                for (final a in assets) {
                  final name = (a["name"] as String).toLowerCase();
                  final url = a["browser_download_url"] as String;
                  final isWin = name.contains('win') ||
                      name.contains('windows') ||
                      name.endsWith('.exe');
                  if (!isWin) continue;

                  // דלג על קובץ full — מיועד להתקנה ראשונית בלבד
                  if (name.contains('-full') || name.contains('_full')) {
                    continue;
                  }

                  // עדיפות ראשונה: קובץ עדכון קטן
                  if (name.contains('-update.exe') ||
                      name.contains('_update.exe')) {
                    return url;
                  }

                  if (name.endsWith('.exe') && regularExe == null) {
                    regularExe = url;
                  }
                  if (allowZipFallback &&
                      name.endsWith('.zip') &&
                      foundZip == null) {
                    foundZip = url;
                  }
                }
                return regularExe ?? foundZip;
              }

              if (platform == 'windows') {
                assetUrl = pickWindows(allowZipFallback: true);
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
            getChangelog: (latestVersion, appVersion) async {
              // Load changelog directly from GitHub repository
              try {
                final response = await http
                    .get(
                      Uri.parse(_changelogUrl),
                    )
                    .timeout(const Duration(seconds: 10));

                if (response.statusCode == 200) {
                  return changelogBetweenVersionsForUpdateDialog(
                    changelog: response.body,
                    currentVersion: appVersion,
                    latestVersion: latestVersion,
                  );
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

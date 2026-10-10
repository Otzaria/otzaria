import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/update_check_frequency.dart';
import 'package:otzaria/core/update_source_reachability.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/services/windows_arch_info.dart';
import 'package:otzaria/utils/file/archive_extractor.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:updat/updat.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:updat/utils/file_handler.dart' show openInstaller;
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'app_release_version.dart';
import 'differential/differential_update_service.dart';
import 'differential/swap_plan.dart' show kSwapBackupDirName;
import 'differential/swap_recovery.dart';
import 'differential/update_engine.dart'
    show fullPackageSwapPlan, writeSwapPlanFile;
import 'differential/installed_release.dart';
import 'differential/zstd_runner.dart';
import 'hebrew_update_widgets.dart';
import 'linux_installer.dart';
import 'macos_installer.dart';
import 'tree_swap.dart';
import 'windows_installer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/settings/settings_exports.dart';

export 'differential/swap_recovery.dart' show differentialWorkDirectory;

/// סוג ההתקנה המוגדר בזמן build (אופציונלי)
/// להגדרה: --dart-define=INSTALL_KIND=exe/zip
const _kInstallKind = String.fromEnvironment(
  'INSTALL_KIND',
  defaultValue: 'auto',
);

const _githubOwner = 'Otzaria';
const _githubRepository = 'otzaria';
const _changelogAssetPath = 'assets/יומן שינויים.md';
const _kGithubTimeout = Duration(seconds: 15);
const _kDownloadConnectTimeout = Duration(seconds: 20);
const _kDownloadStallTimeout = Duration(seconds: 30);

@visibleForTesting
bool supportsManagedUpdatePlatform({
  required bool isWeb,
  required String operatingSystem,
}) {
  if (isWeb) return false;
  return operatingSystem == 'windows' ||
      operatingSystem == 'macos' ||
      operatingSystem == 'linux';
}

/// האם החלון הזה מריץ את מסלול העדכון — בדיקה, הורדה, ו-hook סגירת החלון.
///
/// ⚠️ הפרדיקט חשוף כדי שיהיה **ניתן לבדיקה**. בתוך `build` הוא היה מגודר
/// ב-[kDebugMode], שהוא `true` בכל הרצת בדיקה — כלומר כל מה שהעוטף מתקין
/// קיים ב-release בלבד, ואף בדיקה לא יכלה לגעת בו.
@visibleForTesting
bool managesUpdatesInThisWindow({
  required bool isDebug,
  required bool isSecondaryWindow,
  required bool isWeb,
  required String operatingSystem,
}) {
  if (isDebug) return false;
  // בדיקה, הורדה והתקנה הן פר-תהליך: חלון נוסף היה בודק, מוריד לאותו נתיב
  // ומתקין במקביל לראשון.
  if (isSecondaryWindow) return false;
  return supportsManagedUpdatePlatform(
    isWeb: isWeb,
    operatingSystem: operatingSystem,
  );
}

@visibleForTesting
class InitialSoftwareCheck {
  Completer<bool> _current = Completer<bool>();

  Future<bool> get result => _current.future;

  Completer<bool> begin() {
    if (!_current.isCompleted) _current.complete(false);
    return _current = Completer<bool>();
  }

  void resolve(Completer<bool> check, {required bool updateAvailable}) {
    if (!check.isCompleted) check.complete(updateAvailable);
  }
}

final _initialSoftwareCheck = InitialSoftwareCheck();

/// האם בדיקת התוכנה של העלייה מצאה גרסה חדשה.
/// `false` כשהבדיקה לא רצה (תדירות, מנותק) או נכשלה; בזמן סיור ממתינה לסופו.
Future<bool> initialSoftwareUpdateAvailable() =>
    managesUpdatesInThisWindow(
      isDebug: kDebugMode,
      isSecondaryWindow: WindowRole.isSecondary,
      isWeb: kIsWeb,
      operatingSystem: Platform.operatingSystem,
    )
    ? _initialSoftwareCheck.result
    : Future.value(false);

/// מנסה את מסלול העדכון המצומצם ומחזיר `null` בכל כשל או חוסר זמינות.
///
/// הבליעה היא העיקר: המסלול הזה הוא אופטימיזציה, וכל כשל בו חייב להחזיר
/// את המשתמש למתקין המלא בדיוק כפי שפעל עד כה.
@visibleForTesting
Future<PreparedDifferentialUpdate?> tryPrepareDifferentialUpdate(
  Future<PreparedDifferentialUpdate?> Function() prepare,
) async {
  try {
    return await prepare();
  } catch (error, stackTrace) {
    debugPrint('[Update] small update unavailable: $error\n$stackTrace');
    return null;
  }
}

@visibleForTesting
bool shouldLaunchInstallerOnExit({
  required UpdatStatus status,
  required bool hasInstallerFile,
}) {
  if (!hasInstallerFile) return false;
  return status == UpdatStatus.readyToInstall ||
      status == UpdatStatus.dismissed;
}

/// כשל בשיגור המתקין חייב להשאיר את אוצריא פתוחה עם מצב שגיאה לניסיון חוזר —
/// סגירה בכל מקרה (ההתנהגות הישנה) תוקעת את המשתמש בלי מתקין רץ ובלי אוצריא.
@visibleForTesting
bool shouldDestroyWindowAfterInstallNow({required bool installerLaunched}) =>
    installerLaunched;

/// האם הנכס הוא אשף ההורדות (`Otzaria-Download-Assistant-windows.exe`).
///
/// הוא exe שאינו מתקין, ושיגורו עם מתגי Inno השקטים היה מריץ אשף אקראי
/// במקום לעדכן — ולכן הוא מוחרג מבחירת נכס העדכון.
@visibleForTesting
bool isDownloadAssistantAsset(String assetName) {
  final name = assetName.toLowerCase();
  return name.contains('download-assistant') ||
      name.contains('download_assistant');
}

/// בוחר את קובץ העדכון המתאים ל-Windows מתוך נכסי ה-release.
///
/// בהתקנה רגילה (exe) נבחר המתקין הרגיל — הוא מזהה שדרוג מגרסה קיימת
/// ומתקין את עצמו ברקע ללא אשף, משמר את ההגדרות ומפעיל את אוצריא מחדש
/// בסיום — כך שהעדכון מתבצע כולו מתוך התוכנה. קבצי `full` (עם ספרייה
/// מצורפת) לעולם אינם נבחרים לעדכון.
///
/// [isArmMachine] — המעבד (לא התהליך) קובע את הארכיטקטורה: במחשב ARM
/// מועדף נכס `arm64` וגם התקנת x64 קיימת תשודרג אליו (זה מסלול המעבר
/// היחיד מהאמולציה); בהיעדרו נופלים ל-x64 שעובד באמולציה. במחשב x64
/// נכסי `arm64` לעולם אינם נבחרים.
@visibleForTesting
String? pickWindowsAssetUrl(
  List<Map<String, dynamic>> assets, {
  required String preferredFormat, // 'exe' | 'zip'
  required bool isArmMachine,
}) {
  String? exe;
  String? zip;
  String? armExe;
  String? armZip;

  for (final asset in assets) {
    final name = (asset['name'] as String).toLowerCase();
    final url = asset['browser_download_url'] as String;
    final isWindowsAsset =
        name.contains('win') ||
        name.contains('windows') ||
        name.endsWith('.exe');
    if (!isWindowsAsset) continue;
    if (name.contains('full')) continue;
    if (isDownloadAssistantAsset(name)) continue;
    // חבילת עדכון דיפרנציאלי היא zip חלקי באותו release, לא גרסה ניידת.
    if (name.startsWith('otzaria-update-')) continue;

    final isArmAsset = name.contains('arm64') || name.contains('aarch64');
    if (name.endsWith('.exe')) {
      if (isArmAsset) {
        armExe ??= url;
      } else {
        exe ??= url;
      }
    } else if (name.endsWith('.zip')) {
      if (isArmAsset) {
        armZip ??= url;
      } else {
        zip ??= url;
      }
    }
  }

  if (isArmMachine) {
    if (preferredFormat == 'zip') {
      return armZip ?? armExe ?? zip ?? exe;
    }
    return armExe ?? armZip ?? exe ?? zip;
  }

  if (preferredFormat == 'zip') {
    return zip ?? exe;
  }
  return exe ?? zip;
}

/// בוחר את נכס העדכון המתאים ל-macOS מתוך נכסי ה-release.
///
/// כשהאפליקציה מסוגלת לעדכון עצמי ([selfUpdateCapable], כלומר רצה מ-bundle
/// רגיל — לא Translocation ולא DMG; הרשאת הכתיבה בפועל נבדקת בסקריפט העדכון
/// בזמן ההחלפה) — מעדיפים את ה-zip של האפליקציה בלבד
/// (`otzaria-macos.zip`), שמוחלף ברקע על ידי סקריפט העדכון. אחרת בוחרים
/// **רק** DMG, שנפתח להתקנה ידנית בגרירה: zip ללא עדכון עצמי הוא נתיב
/// שבור — הוא אינו מחולץ ב-Dart במאק (ראה `downloadReleaseFile`) ולכן
/// `openInstaller` ייכשל עליו. קבצי `full` לעולם אינם נבחרים — הם חבילות
/// ספרייה מלאות ולא עדכוני תוכנה.
@visibleForTesting
String? pickMacAssetUrl(
  List<Map<String, dynamic>> assets, {
  required bool selfUpdateCapable,
}) {
  String? zip;
  String? dmg;

  for (final asset in assets) {
    final name = (asset['name'] as String).toLowerCase();
    final url = asset['browser_download_url'] as String;
    final isMacAsset =
        name.contains('macos') ||
        name.contains('darwin') ||
        name.contains('mac');
    if (!isMacAsset) continue;
    if (name.contains('full')) continue;
    if (isDownloadAssistantAsset(name)) continue;

    if (name.endsWith('.zip')) zip ??= url;
    if (name.endsWith('.dmg')) dmg ??= url;
  }

  if (selfUpdateCapable) {
    return zip ?? dmg;
  }
  return dmg;
}

/// בוחר את נכס העדכון ל-Linux: חבילת DEB, אחריה RPM, ובהיעדר שתיהן ZIP
/// של Linux — רק בארכיטקטורה של המכונה. מסייע ההורדה לעולם אינו נבחר.
///
/// הנכס ל-x64 אינו מסומן בשמו, ולכן ARM מזוהה לפי `arm64`/`aarch64` בלבד.
/// בהתקנה ניידת ([isPortableInstall]) אין נכס כזה: deb היה מתקין עותק
/// נפרד ב-‎/opt‎, והעותק שהמשתמש מריץ לא היה מתעדכן לעולם.
@visibleForTesting
String? pickLinuxAssetUrl(
  List<Map<String, dynamic>> assets, {
  required bool isArm64,
  bool isPortableInstall = false,
}) {
  if (isPortableInstall) return null;
  String? firstWhere(bool Function(String name) matches) {
    for (final asset in assets) {
      final name = (asset['name'] as String).toLowerCase();
      if (isDownloadAssistantAsset(name)) continue;
      final isArmAsset = name.contains('arm64') || name.contains('aarch64');
      if (isArmAsset != isArm64) continue;
      if (matches(name)) return asset['browser_download_url'] as String;
    }
    return null;
  }

  return firstWhere((n) => n.endsWith('.deb')) ??
      firstWhere((n) => n.endsWith('.rpm')) ??
      firstWhere(
        (n) => (n.contains('linux') || n.contains('gnu')) && n.endsWith('.zip'),
      );
}

/// האם ה-URL מצביע על מתקין Windows שמתקין שדרוג בשקט.
///
/// כל מתקיני ה-exe מזהים שדרוג מגרסה קיימת ומתקינים ברקע, והעדכון תמיד
/// לגרסה חדשה מהנוכחית — לכן כל exe שנבחר הוא כזה. ההכרעה לפי ה-URL
/// (שמשמר את שם הנכס ב-release) ולא לפי הקובץ שהורד, כי שם הקובץ המקומי
/// אחיד (`otzaria-<version>.exe`).
@visibleForTesting
bool isSilentWindowsInstallerUrl(String url) {
  final name = url.split('/').last.toLowerCase();
  return name.endsWith('.exe');
}

/// מטמון של תוצאות GitHub API. המפתח כולל גם את הערוץ (stable/dev) כדי למנוע
/// דליפה בין ערוצים אם המשתמש מחליף הגדרה באותו סשן, וגם כדי שלא יחזרו
/// תוצאות ישנות כאשר שני release-ים בערוץ dev חולקים אותה core version
/// (כגון `0.9.92+628` ו-`0.9.92+629`).
@visibleForTesting
final Map<String, Map<String, dynamic>> releaseCacheForTesting = {};

bool _isDevChannelEnabled() =>
    Settings.getValue<bool>('key-dev-channel') ?? false;

String _cacheKey(String version, {bool? isDev}) {
  final dev = isDev ?? _isDevChannelEnabled();
  return '${dev ? 'dev' : 'stable'}:$version';
}

/// מאחסן release ב-cache עבור גרסה נתונה. נקרא מ-`getLatestVersion` כדי
/// להבטיח ש-`getChangelog`/`getBinaryUrl` מקבלים בדיוק את ה-release שזוהה
/// כ"החדש ביותר", ולא נבחר מחדש לפי prefix.
void _cacheRelease(
  String version,
  Map<String, dynamic> release, {
  bool? isDev,
}) {
  releaseCacheForTesting[_cacheKey(version, isDev: isDev)] = release;
}

/// בוחר את ה-release ה-pre-release האחרון ברשימה שמתאים לערוץ dev:
/// pre-release אמיתי, לא draft, ולא PR preview (tag שלא מכיל `-pr`).
/// אם אין התאמה — נופל ל-release הראשון ברשימה (כדי להתאים להתנהגות הקודמת).
/// מקבלת `List<dynamic>` ישירות מ-`jsonDecode` ולא מסתמכת על הסקה גנרית
/// של `firstWhere` שמשתנה לפי הטיפוס בזמן ריצה.
@visibleForTesting
Map<String, dynamic> pickLatestDevRelease(List<dynamic> releases) {
  for (final r in releases) {
    if (r is Map &&
        r["prerelease"] == true &&
        r["draft"] == false &&
        !r["tag_name"].toString().contains('-pr')) {
      return r.cast<String, dynamic>();
    }
  }
  return (releases.first as Map).cast<String, dynamic>();
}

/// בערוץ המפתחים בוחר את ה-release היציב אם הוא חדש מה-pre-release האחרון.
/// בשוויון גרסה (בלי `+build`) מוחזר ה-stable, כדי לעגן אליו את ה-changelog והנכסים.
@visibleForTesting
Map<String, dynamic> pickPreferredReleaseForDevChannel({
  required Map<String, dynamic> stableRelease,
  required Map<String, dynamic> devRelease,
}) {
  final stableTag = stableRelease['tag_name']?.toString() ?? '';
  final devTag = devRelease['tag_name']?.toString() ?? '';
  final stableVersion = _tryParseVersion(stableTag);
  final devVersion = _tryParseVersion(devTag);

  if (stableVersion == null) return devRelease;
  if (devVersion == null) return stableRelease;

  return devVersion > stableVersion ? devRelease : stableRelease;
}

/// שולפת את מידע ה-release מ-GitHub עבור גרסה נתונה ושומרת אותו במטמון.
/// אם `getLatestVersion` כבר הקדים לאחסן את ה-release המדויק שזוהה, נחזיר
/// אותו ישירות — כך מובטח עקביות בין ה-release שזוהה כ"חדש" לבין
/// ה-changelog וקובץ ההתקנה.
Future<Map<String, dynamic>> _fetchRelease(String version) async {
  final cached = releaseCacheForTesting[_cacheKey(version)];
  if (cached != null) return cached;

  final isDev = _isDevChannelEnabled();
  Map<String, dynamic> release;

  if (isDev) {
    final data = await http
        .get(
          Uri.parse(
            "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases",
          ),
        )
        .timeout(_kGithubTimeout);
    final releases = jsonDecode(data.body) as List;
    final byPrefix = releases
        .where(
          (r) => releaseTagMatchesVersion(r["tag_name"].toString(), version),
        )
        .toList();
    final pool = byPrefix.isNotEmpty ? byPrefix : releases;
    release = pickLatestDevRelease(pool);
  } else {
    var resp = await http
        .get(
          Uri.parse(
            "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/tags/$version",
          ),
        )
        .timeout(_kGithubTimeout);
    if (resp.statusCode == 404) {
      resp = await http
          .get(
            Uri.parse(
              "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/tags/v$version",
            ),
          )
          .timeout(_kGithubTimeout);
    }
    if (resp.statusCode >= 400) {
      throw Exception(
        'Release "$version" not found (status ${resp.statusCode})',
      );
    }
    release = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
  }

  _cacheRelease(version, release, isDev: isDev);
  return release;
}

/// האם [tag] הוא שחרור של [version] בדיוק: `0.9.97` תופס את `0.9.97+789`
/// ולא את ה-hotfix `0.9.97.2+790`.
@visibleForTesting
bool releaseTagMatchesVersion(String tag, String version) =>
    tag == version || tag.startsWith('$version+');

/// בונה URL לקובץ raw בריפו, צמוד לתג הספציפי של ה-release.
/// שימוש ב-`pathSegments` מבטיח קידוד נכון של תווים מיוחדים כמו `+` שבתגים
/// בערוץ dev (לדוגמה `0.9.92+628`) ושל תווי יוניקוד בנתיב.
@visibleForTesting
Uri rawAssetUrlForTag(String tagName, String relativePath) {
  final segments = <String>[
    _githubOwner,
    _githubRepository,
    'refs',
    'tags',
    tagName,
    ...relativePath.split('/'),
  ];
  return Uri(
    scheme: 'https',
    host: 'raw.githubusercontent.com',
    pathSegments: segments,
  );
}

final _changelogHeadingPattern = RegExp(
  r'^\s*(?:(?:#{1,6}|[*-])\s*)?\*{0,2}v?(\d+(?:\.\d+){1,3}(?:[-+][^\s*]+)?)\*{0,2}\s*$',
);

class _ParsedVersion implements Comparable<_ParsedVersion> {
  final int major;
  final int minor;
  final int patch;
  final int hotfix;

  const _ParsedVersion(this.major, this.minor, this.patch, this.hotfix);

  @override
  int compareTo(_ParsedVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) return majorCompare;

    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) return minorCompare;

    final patchCompare = patch.compareTo(other.patch);
    if (patchCompare != 0) return patchCompare;

    return hotfix.compareTo(other.hotfix);
  }

  bool operator >(_ParsedVersion other) => compareTo(other) > 0;

  bool operator <=(_ParsedVersion other) => compareTo(other) <= 0;

  @override
  String toString() =>
      hotfix > 0 ? '$major.$minor.$patch.$hotfix' : '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ParsedVersion &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch &&
          hotfix == other.hotfix;

  @override
  int get hashCode => Object.hash(major, minor, patch, hotfix);
}

/// בוחר פורמט עדכון לפי סוג ההתקנה: מתקין (`exe`) לאפליקציה מותקנת, או
/// חבילה ניידת (`zip`) לחילוץ ידני.
@visibleForTesting
String preferredWindowsFormatForInstall({required bool isInstalledApp}) =>
    isInstalledApp ? 'exe' : 'zip';

/// זיהוי פורמט העדכון ב-Windows. אם הוגדר INSTALL_KIND בזמן build - משתמש בו;
/// אחרת לפי האות האחיד [AppPaths.isPortable] (קובץ portable.marker ליד ה-EXE):
/// נייד → zip, מותקן (admin או per-user) → מתקין exe.
String _preferredWindowsFormat() {
  if (!Platform.isWindows) return 'unknown';
  if (_kInstallKind != 'auto') return _kInstallKind; // 'exe' | 'zip'
  return preferredWindowsFormatForInstall(isInstalledApp: !AppPaths.isPortable);
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
  if (parts.length < 2 || parts.length > 4) return null;

  final major = int.tryParse(parts[0]);
  final minor = int.tryParse(parts[1]);
  final patch = parts.length >= 3 ? int.tryParse(parts[2]) : 0;
  final hotfix = parts.length == 4 ? int.tryParse(parts[3]) : 0;
  if (major == null || minor == null || patch == null || hotfix == null) {
    return null;
  }

  return _ParsedVersion(major, minor, patch, hotfix);
}

/// האם [latestVersion] חדשה מ-[currentVersion]; גרסה שאינה ניתנת לפענוח אינה עדכון.
@visibleForTesting
bool isNewerReleaseVersion({
  required String latestVersion,
  required String currentVersion,
}) {
  final latest = _tryParseVersion(latestVersion);
  final current = _tryParseVersion(currentVersion);
  return latest != null && current != null && latest > current;
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
      includeCurrentSection =
          headingVersion != null &&
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

/// תיקיית העבודה של מנגנון העדכון. קובץ ההתקנה הוא קובץ זמני של אוצריא ולא
/// הורדה של המשתמש — הורדה לתיקיית ההורדות שלו הותירה שם קבצי מתקין כבדים
/// שאיש אינו מנקה.
@visibleForTesting
Directory updateWorkingDirectory() =>
    Directory(p.join(Directory.systemTemp.path, 'otzaria_update'));

/// מחזירה נתיב חדש לקובץ העדכון, ומנקה תחילה שאריות מהורדות קודמות.
@visibleForTesting
Future<File> prepareUpdateInstallerFile({
  required String version,
  required String extension,
}) async {
  final dir = updateWorkingDirectory();
  if (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // שארית נעולה (מתקין קודם שעדיין רץ) אינה סיבה להכשיל את העדכון.
    }
  }
  await dir.create(recursive: true);
  return File(p.join(dir.path, 'otzaria-$version.$extension'));
}

/// האם בדיקת עדכונים חסומה כרגע (מצב מנותק או שעדכוני תוכנה כובו בהגדרות).
bool updateCheckBlocked({
  required bool isOfflineMode,
  required bool updatesEnabled,
}) => isOfflineMode || !updatesEnabled;

/// הודעת הכשל להצגה אחרי בדיקת עדכון שנכשלה, או `null` כשאין להציג דבר:
/// כששרת העדכונים אינו נגיש (אין רשת, או שהרשת מסננת אותו) זו אינה תקלה של
/// אוצריא ואין למשתמש מה לעשות איתה.
@visibleForTesting
String? updateCheckFailureMessage({
  required bool isNetworkError,
  required bool isSourceReachable,
}) {
  if (!isSourceReachable) return null;
  return isNetworkError
      ? LibraryMessages.updateCheckNetworkError
      : LibraryMessages.updateCheckError;
}

/// השהיה עד הניסיון החוזר ה-[attempt] אחרי בדיקה שנכשלה בהיעדר אינטרנט;
/// `null` = די בניסיונות.
@visibleForTesting
Duration? offlineRecheckDelay(int attempt) => switch (attempt) {
  0 => const Duration(minutes: 2),
  1 => const Duration(minutes: 5),
  2 => const Duration(minutes: 15),
  _ => null,
};

/// האם להריץ בדיקת עדכון מחדש לאחר שינוי הגדרות: רק במעבר מחסימה לזמינות,
/// וכשאין בדיקה/הורדה/התקנה בעיצומן (upToDate הוא גם המצב שנקבע בעת חסימה).
@visibleForTesting
bool shouldRecheckAfterUnblock({
  required bool wasBlocked,
  required bool isBlocked,
  required UpdatStatus status,
}) => wasBlocked && !isBlocked && status == UpdatStatus.upToDate;

class MyUpdatWidget extends StatelessWidget {
  const MyUpdatWidget({super.key, required this.child});

  final Widget child;
  @override
  Widget build(BuildContext context) {
    // אסור שצורת העץ תלויה בהגדרות משתנות (מנותק/עדכונים) — החלפת העוטף
    // בזמן ריצה בונה מחדש את כל תת-העץ וה-PageView מאבד את העמוד הפעיל.
    if (!managesUpdatesInThisWindow(
      isDebug: kDebugMode,
      isSecondaryWindow: WindowRole.isSecondary,
      isWeb: kIsWeb,
      operatingSystem: Platform.operatingSystem,
    )) {
      return child;
    }
    return _ManagedUpdatWidget(child: child);
  }
}

class _ManagedUpdatWidget extends StatefulWidget {
  const _ManagedUpdatWidget({required this.child});

  final Widget child;

  @override
  State<_ManagedUpdatWidget> createState() => _ManagedUpdatWidgetState();
}

class _ManagedUpdatWidgetState extends State<_ManagedUpdatWidget> {
  late final Completer<bool> _softwareCheck;
  UpdatStatus _status = UpdatStatus.checking;
  String? _currentVersion;
  String? _latestVersion;
  String? _changelog;
  File? _installerFile;

  /// האם הקובץ ב-[_installerFile] הוא מתקין Windows שמתקין בשקט (נקבע לפי
  /// ה-URL בעת ההורדה — ראה [isSilentWindowsInstallerUrl]).
  bool _installerIsSilent = false;
  Future<bool>? _installerLaunch;

  /// עדכון מצומצם שכבר נבנה ואומת ב-staging. קיומו מסיט את ההתקנה
  /// למעדכן העצמאי במקום למתקין המלא.
  PreparedDifferentialUpdate? _differentialUpdate;

  /// ההתקנה החלה; הכפתור נעול בזמן השיגור ועד לסגירת החלונות.
  bool _awaitingCloseForUpdate = false;

  /// פעיל רק כל עוד המעדכן המצומצם ממתין ליציאת התהליך.
  Timer? _updaterGiveUpWatch;

  /// מנוי על מצב הסיור המודרך, פעיל רק כל עוד אנו ממתינים לסיומו לפני
  /// בדיקת העדכון הראשונית.
  StreamSubscription<TourState>? _tourSubscription;

  /// מסמן שהבדיקה האוטומטית הראשונית כבר הופעלה, כדי שלא תופעל פעמיים.
  bool _initialCheckTriggered = false;

  StreamSubscription<SettingsState>? _settingsSubscription;
  late bool _updateCheckWasBlocked;

  /// ניסיונות חוזרים לבדיקה שנכשלה בהיעדר אינטרנט — ראה [_scheduleOfflineRecheck].
  Timer? _offlineRecheckTimer;
  int _offlineRecheckAttempt = 0;

  /// נתפס פעם אחת ולא נשלף בזמן הסגירה: `_handleWindowClose` רץ כשהעץ כבר
  /// מתפרק, ו-`controllerOf` הוא חיפוש בעץ ה-widgets.
  late AppWindowController _appWindow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appWindow = AppWindowScope.controllerOf(context);
  }

  @override
  void initState() {
    super.initState();
    _softwareCheck = _initialSoftwareCheck.begin();
    AppWindowListener.prepareUpdateForClose = _handleWindowClose;
    _listenForUpdateUnblock();
    // דוחים את הבדיקה הראשונית ל-post-frame כדי שהסיור המודרך (שמופעל אף הוא
    // ב-post-frame, מוקדם יותר באותו פריים) יספיק לעדכן את מצבו לפני שנחליט.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startInitialUpdateCheckRespectingTour();
    });
  }

  /// כשהבדיקה נחסמה (מנותק/עדכונים כבויים) המצב נקבע ל-upToDate ואיש לא
  /// יבדוק שוב — לכן מאזינים ל-SettingsBloc ובודקים מחדש במעבר לזמינות.
  void _listenForUpdateUnblock() {
    final settingsBloc = context.read<SettingsBloc>();
    _updateCheckWasBlocked = !settingsBloc.state.canUseSoftwareAndBookUpdates;
    _settingsSubscription = settingsBloc.stream.listen((settingsState) {
      final isBlocked = !settingsState.canUseSoftwareAndBookUpdates;
      final shouldRecheck = shouldRecheckAfterUnblock(
        wasBlocked: _updateCheckWasBlocked,
        isBlocked: isBlocked,
        status: _status,
      );
      _updateCheckWasBlocked = isBlocked;
      if (shouldRecheck && _initialCheckTriggered && mounted) {
        _checkForUpdate();
      }
    });
  }

  /// מפעיל את בדיקת העדכון הראשונית רק כשהסיור המודרך אינו פעיל. אם הסיור פעיל,
  /// מאזין למצבו וממתין עד שיסתיים (סיום או דילוג) לפני הבדיקה.
  void _startInitialUpdateCheckRespectingTour() {
    if (_initialCheckTriggered) return;
    final tourCubit = context.read<TourCubit>();
    if (!tourCubit.state.isActive) {
      _initialCheckTriggered = true;
      _runInitialCheckIfDue();
      return;
    }
    _tourSubscription ??= tourCubit.stream.listen((tourState) {
      if (tourState.isActive || _initialCheckTriggered) return;
      _initialCheckTriggered = true;
      _tourSubscription?.cancel();
      _tourSubscription = null;
      if (mounted) _runInitialCheckIfDue();
    });
  }

  /// הבדיקה האוטומטית בעלייה כפופה לתדירות שנבחרה בהגדרות; בדיקה יזומה
  /// (הצ'יפ בשורת הכותרת) קוראת ל-[_checkForUpdate] ישירות ואינה מושפעת.
  void _runInitialCheckIfDue() {
    if (!isAutoUpdateCheckDue(SettingsRepository.keyLastSoftwareUpdateCheck)) {
      _initialSoftwareCheck.resolve(_softwareCheck, updateAvailable: false);
      setState(() {
        _status = UpdatStatus.upToDate;
      });
      return;
    }
    _checkForUpdate().whenComplete(
      () => _initialSoftwareCheck.resolve(
        _softwareCheck,
        updateAvailable: _status == UpdatStatus.availableWithChangelog,
      ),
    );
  }

  @override
  void dispose() {
    _initialSoftwareCheck.resolve(_softwareCheck, updateAvailable: false);
    _tourSubscription?.cancel();
    _settingsSubscription?.cancel();
    _offlineRecheckTimer?.cancel();
    _updaterGiveUpWatch?.cancel();
    if (AppWindowListener.prepareUpdateForClose == _handleWindowClose) {
      AppWindowListener.prepareUpdateForClose = null;
    }
    super.dispose();
  }

  void _showUpdateError(String message) {
    if (!mounted) return;
    setState(() {
      _status = UpdatStatus.dismissed;
    });
    UiSnack.showError(message);
  }

  Future<void> _handleWindowClose() async {
    // שיגור שכבר התחיל חייב להסתיים לפני שהכיבוי מסיים את התהליך.
    final pending = _installerLaunch;
    if (pending != null) {
      await pending;
      return;
    }
    if (!shouldLaunchInstallerOnExit(
      status: _status,
      hasInstallerFile: _installerFile != null || _differentialUpdate != null,
    )) {
      return;
    }
    // המשתמש סוגר את התוכנה — העדכון מותקן ברקע, אך אין להפעיל את
    // אוצריא מחדש בסיום בניגוד לכוונתו.
    final launched = await _launchInstaller(relaunchApp: false);
    if (launched) {
      _installerFile = null;
      _differentialUpdate = null;
    }
  }

  /// משגר את העדכון ביוזמת המשתמש וסוגר את אוצריא רק אם השיגור הצליח.
  Future<void> _installNow() async {
    if (_awaitingCloseForUpdate || _installerLaunch != null) return;
    if (_installerFile == null && _differentialUpdate == null) return;
    setState(() => _awaitingCloseForUpdate = true);
    final differential = _differentialUpdate;
    final installer = _installerFile;
    final launched = await _launchInstaller(relaunchApp: true);
    if (!launched && mounted) {
      setState(() => _awaitingCloseForUpdate = false);
    }
    if (shouldDestroyWindowAfterInstallNow(installerLaunched: launched)) {
      // איפוס המקורות מונע שיגור כפול כשאירוע הסגירה יגיע ל-hook.
      _installerFile = null;
      _differentialUpdate = null;
      final portableZip =
          Platform.isWindows &&
          (installer?.path.toLowerCase().endsWith('.zip') ?? false);
      final updaterWorkRoot =
          differential?.staged.workRoot ??
          (portableZip ? differentialWorkDirectory() : null);
      if (updaterWorkRoot != null) {
        _updaterGiveUpWatch?.cancel();
        _updaterGiveUpWatch = watchForUpdaterGiveUp(
          updaterWorkRoot,
          () => _restorePreparedUpdate(
            differential: differential,
            installer: installer,
          ),
        );
      }
      // ⚠️ המעדכן מחליף קבצים רק אחרי שהתהליך יצא, וכל חלון הוא isolate
      // נפרד. חלון שיסרב להיסגר פשוט משאיר את המעדכן ממתין — אי-אירוע.
      MultiWindowService.closePeers();
      // ⚠️ סגירה מנומסת ולא `quitApplication()`: האחרון הוא `PostQuitMessage`
      // ומפיל את המנוע תחת Dart רץ. ראו התיעוד ב-`AppWindowController`.
      await _appWindow.close();
    }
  }

  /// המעדכן ויתר לפני שנגע בהתקנה — חוזרים ל"מוכן להתקנה" עם אותו staging.
  void _restorePreparedUpdate({
    PreparedDifferentialUpdate? differential,
    File? installer,
  }) {
    if (!mounted) return;
    setState(() {
      _differentialUpdate = differential;
      _installerFile = installer;
      _awaitingCloseForUpdate = false;
      _status = UpdatStatus.readyToInstall;
    });
    UiSnack.showError(LibraryMessages.smallUpdateGaveUp);
  }

  Future<void> _checkForUpdate() async {
    if (updateCheckBlocked(
      isOfflineMode:
          Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false,
      updatesEnabled:
          Settings.getValue<bool>(
            SettingsRepository.keySoftwareAndBookUpdatesEnabled,
            defaultValue: true,
          ) ??
          true,
    )) {
      setState(() {
        _status = UpdatStatus.upToDate;
      });
      return;
    }

    setState(() {
      _status = UpdatStatus.checking;
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = appReleaseVersion(packageInfo);
      final latestVersion = await _getLatestVersion();

      if (!mounted) return;
      // הבדיקה עברה — ניתוק עתידי יקבל שוב מכסת ניסיונות מלאה.
      _offlineRecheckAttempt = 0;
      unawaited(
        recordSuccessfulUpdateCheck(
          SettingsRepository.keyLastSoftwareUpdateCheck,
        ),
      );

      if (latestVersion == null) {
        setState(() {
          _currentVersion = currentVersion;
          _status = UpdatStatus.upToDate;
        });
        return;
      }

      if (isNewerReleaseVersion(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
      )) {
        final changelog = await _getChangelog(latestVersion, currentVersion);
        if (!mounted) return;
        setState(() {
          _currentVersion = currentVersion;
          _latestVersion = latestVersion;
          _changelog = changelog;
          _status = UpdatStatus.availableWithChangelog;
        });
        return;
      }

      setState(() {
        _currentVersion = currentVersion;
        _latestVersion = latestVersion;
        _status = UpdatStatus.upToDate;
      });
    } catch (e, st) {
      debugPrint('[Update] update check failed: $e\n$st');
      // כשל רשת ≠ כשל parsing של תשובת GitHub — הודעת 'רשת' על באג parsing
      // הסתירה את הבעיה האמיתית.
      final isNetwork =
          e is SocketException ||
          e is TimeoutException ||
          e is http.ClientException;
      // נבדקת נגישות GitHub עצמו ולא "יש אינטרנט": ברשת מסוננת החיבור הכללי
      // עובד, אך העדכון נכשל בכל עלייה — והשגיאה היא רעש שאין לו מענה.
      final message = updateCheckFailureMessage(
        isNetworkError: isNetwork,
        isSourceReachable: await isUpdateSourceReachable(),
      );
      if (!mounted) return;
      if (message == null) {
        setState(() {
          _status = UpdatStatus.upToDate;
        });
        _scheduleOfflineRecheck();
        return;
      }
      _showUpdateError(message);
    }
  }

  /// מנותק בפתיחה אינו סוף פסוק: בודקים שוב בהשהיות עולות, כדי שמי שהתחבר
  /// אחרי הפתיחה יקבל את העדכון בלי להפעיל מחדש את אוצריא.
  void _scheduleOfflineRecheck() {
    final delay = offlineRecheckDelay(_offlineRecheckAttempt);
    if (delay == null) return;
    _offlineRecheckAttempt++;
    _offlineRecheckTimer?.cancel();
    _offlineRecheckTimer = Timer(delay, () {
      // upToDate הוא המצב שנקבע בכשל המנותק — כל מצב אחר מסמן בדיקה/הורדה
      // חדשה שאין להפריע לה.
      if (mounted && _status == UpdatStatus.upToDate) _checkForUpdate();
    });
  }

  Future<String?> _getLatestVersion() async {
    releaseCacheForTesting.clear();

    final isDevChannel = _isDevChannelEnabled();

    if (isDevChannel) {
      final devData = await http
          .get(
            Uri.parse(
              "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases",
            ),
          )
          .timeout(_kGithubTimeout);
      final stableData = await http
          .get(
            Uri.parse(
              "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/latest",
            ),
          )
          .timeout(_kGithubTimeout);
      final releases = jsonDecode(devData.body) as List;
      final preRelease = pickLatestDevRelease(releases);
      final stableRelease = (jsonDecode(stableData.body) as Map)
          .cast<String, dynamic>();
      final selectedRelease = pickPreferredReleaseForDevChannel(
        stableRelease: stableRelease,
        devRelease: preRelease,
      );
      final normalized = _normalizeVersion(
        selectedRelease["tag_name"] as String,
      );
      _cacheRelease(normalized, selectedRelease, isDev: true);
      return normalized;
    }

    final data = await http
        .get(
          Uri.parse(
            "https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/latest",
          ),
        )
        .timeout(_kGithubTimeout);
    final release = (jsonDecode(data.body) as Map).cast<String, dynamic>();
    final normalized = _normalizeVersion(release["tag_name"] as String);
    _cacheRelease(normalized, release, isDev: false);
    return normalized;
  }

  Future<String> _getBinaryUrl(String version) async {
    final release = await _fetchRelease(version).timeout(_kGithubTimeout);
    final assets = (release["assets"] as List).cast<Map<String, dynamic>>();
    final platform = Platform.operatingSystem.toLowerCase();

    String? assetUrl;

    if (platform == 'windows') {
      assetUrl = pickWindowsAssetUrl(
        assets,
        preferredFormat: _preferredWindowsFormat(),
        isArmMachine: WindowsArchInfo.isWindowsOnArm,
      );
    } else if (platform == 'macos') {
      assetUrl = pickMacAssetUrl(
        assets,
        selfUpdateCapable: findInstalledMacAppBundlePath() != null,
      );
    } else if (platform == 'linux') {
      assetUrl = pickLinuxAssetUrl(
        assets,
        isArm64: Abi.current() == Abi.linuxArm64,
        isPortableInstall: _isLinuxPortableInstall(),
      );
    }

    if (assetUrl == null) {
      throw Exception('No suitable binary found for $platform');
    }
    return assetUrl;
  }

  Future<String> _getChangelog(String latestVersion, String appVersion) async {
    try {
      final release = await _fetchRelease(latestVersion);
      final tagName = release['tag_name'] as String;
      final url = rawAssetUrlForTag(tagName, _changelogAssetPath);
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return changelogBetweenVersionsForUpdateDialog(
          changelog: response.body,
          currentVersion: appVersion,
          latestVersion: latestVersion,
        );
      }
      return 'שגיאה בטעינת יומן השינויים.\nקוד שגיאה: ${response.statusCode}';
    } catch (e) {
      return 'שגיאה בטעינת יומן השינויים: $e';
    }
  }

  Future<void> _startUpdate() async {
    if (_latestVersion == null) {
      return;
    }

    if (_status == UpdatStatus.readyToInstall) {
      return _installNow();
    }

    if (_status != UpdatStatus.available &&
        _status != UpdatStatus.availableWithChangelog) {
      return;
    }

    setState(() {
      _status = UpdatStatus.downloading;
    });

    // המסלול המצומצם קודם; כל כשל בו נבלע וממשיכים למתקין המלא כרגיל.
    final differential = await tryPrepareDifferentialUpdate(
      _prepareDifferentialUpdate,
    );
    if (differential != null) {
      if (!mounted) return;
      setState(() {
        _differentialUpdate = differential;
        _status = UpdatStatus.readyToInstall;
      });
      return;
    }

    if (Platform.isLinux && _isLinuxPortableInstall()) {
      await _openReleasePageForManualUpdate();
      return;
    }
    if (Platform.isWindows &&
        _preferredWindowsFormat() == 'zip' &&
        !_canSwapWindowsPortable()) {
      await _openReleasePageForManualUpdate();
      return;
    }

    try {
      final url = await _getBinaryUrl(_latestVersion!).timeout(_kGithubTimeout);
      final installerFile = await prepareUpdateInstallerFile(
        version: _latestVersion!,
        extension: url.split('.').last,
      );
      await downloadReleaseFile(installerFile, url, 'otzaria');

      if (!mounted) return;
      setState(() {
        _installerFile = installerFile;
        _installerIsSilent = isSilentWindowsInstallerUrl(url);
        _status = UpdatStatus.readyToInstall;
      });
    } catch (e, st) {
      debugPrint('[Update] download failed: $e\n$st');
      _showUpdateError(LibraryMessages.updateDownloadError);
    }
  }

  /// האם זו התקנת Linux ניידת — `portable.marker`, או עותק מחבילת ה-FULL
  /// (חותם שחרור מחוץ לנתיבי מנהל החבילות).
  bool _isLinuxPortableInstall() {
    if (AppPaths.isPortable) return true;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return isLinuxPortableInstall(
      executableDirectory: exeDir,
      hasReleaseStamp:
          readInstalledReleaseTag(
            Directory(exeDir),
            platform: 'linux',
            architecture: Abi.current() == Abi.linuxArm64 ? 'arm64' : 'x64',
          ) !=
          null,
    );
  }

  /// להתקנה ניידת אין מתקין: דף ההורדות נפתח, והמשתמש פורס את החבילה.
  Future<void> _openReleasePageForManualUpdate() async {
    try {
      final release = await _fetchRelease(
        _latestVersion!,
      ).timeout(_kGithubTimeout);
      final url = release['html_url'];
      if (url is! String || !await launchUrl(Uri.parse(url))) {
        throw Exception('the release page could not be opened');
      }
      if (!mounted) return;
      setState(() => _status = UpdatStatus.dismissed);
      UiSnack.show(LibraryMessages.portableUpdateOpenedReleasePage);
    } catch (e, st) {
      debugPrint('[Update] release page failed: $e\n$st');
      _showUpdateError(LibraryMessages.updateDownloadError);
    }
  }

  /// עדכון עץ (macOS, Linux נייד): עותק של ההתקנה לצידה, החבילה מוחלת
  /// עליו ומאומתת מול העץ החדש, וההחלפה היא שינוי שם אחרי היציאה.
  Future<PreparedDifferentialUpdate?> _prepareTreeUpdate() async {
    final target = treeInstallTargetFor(
      isMacOS: Platform.isMacOS,
      executablePath: Platform.resolvedExecutable,
      isArm64: Abi.current() == Abi.linuxArm64,
      macBundlePath: Platform.isMacOS ? findInstalledMacAppBundlePath() : null,
    );
    if (target == null) return null;
    final installedReleaseTag = readInstalledReleaseTag(
      Directory(target.stampDirectory),
      platform: target.platform,
      architecture: target.architecture,
    );
    if (installedReleaseTag == null) return null;
    if (Platform.isLinux &&
        !isLinuxPortableInstall(
          executableDirectory: target.installRoot,
          hasReleaseStamp: true,
        )) {
      return null;
    }

    final installRoot = Directory(target.installRoot);
    if (!treeUpdateSupported(
      installRootWritable: isDirectoryWritable(installRoot),
      parentWritable: isDirectoryWritable(installRoot.parent),
      zstdAvailable: await const ZstdRunner.bundled().isAvailable,
      swapHelperAvailable: atomicTreeSwapHelperFor(
        Platform.resolvedExecutable,
      ).existsSync(),
      hasUserData: installRootHasUserData(installRoot),
    )) {
      return null;
    }
    if (!await atomicTreeSwapSupported(
      installRoot,
      atomicTreeSwapHelperFor(Platform.resolvedExecutable),
    )) {
      return null;
    }

    final release = await _fetchRelease(
      _latestVersion!,
    ).timeout(_kGithubTimeout);
    final toReleaseTag = release['tag_name'] as String;

    final work = differentialWorkDirectory();
    if (work.existsSync()) work.deleteSync(recursive: true);

    final service = DifferentialUpdateService(
      installRoot: installRoot,
      workRoot: work,
      platform: target.platform,
      architecture: target.architecture,
      installedReleaseTag: installedReleaseTag,
      preparedRoot: preparedTreeDirectoryFor(installRoot),
      allowUnmanagedFiles: Platform.isLinux,
      download: (url, target, {int? expectedSize}) async {
        await downloadReleaseFile(
          target,
          url,
          'otzaria-small-update',
          expectedSize: expectedSize,
        );
        return target;
      },
    );
    return await service.prepare(toReleaseTag);
  }

  /// בונה את העדכון המצומצם: איתור החבילה, הורדתה ובנייה מאומתת ב-staging.
  /// מחזיר `null` כשהמסלול אינו זמין בהתקנה הזאת.
  Future<PreparedDifferentialUpdate?> _prepareDifferentialUpdate() async {
    if (_latestVersion == null) return null;
    if (Platform.isMacOS || Platform.isLinux) return _prepareTreeUpdate();
    if (!Platform.isWindows) return null;

    final installRoot = Directory(p.dirname(Platform.resolvedExecutable));
    final architecture = installedWindowsArchitecture(
      isWindowsOnArm: WindowsArchInfo.isWindowsOnArm,
      isEmulatedOnArm: WindowsArchInfo.isEmulatedOnArm,
    );
    // תג השחרור המותקן נקרא מהחותם שבתיקיית ההתקנה: PackageInfo מחזיר
    // `0.9.97` בעוד התג האמיתי הוא `0.9.97+789`, ואין חבילה בשם כזה.
    final installedReleaseTag = readInstalledReleaseTag(
      installRoot,
      platform: 'windows',
      architecture: architecture,
    );
    if (installedReleaseTag == null) return null;

    final helper = File(p.join(installRoot.path, 'otzaria_updater.exe'));
    if (!differentialUpdateSupported(
      isWindows: Platform.isWindows,
      installRootWritable: isDirectoryWritable(installRoot),
      zstdAvailable: await const ZstdRunner.bundled().isAvailable,
      hasUpdaterHelper: helper.existsSync(),
    )) {
      return null;
    }

    final release = await _fetchRelease(_latestVersion!).timeout(
      _kGithubTimeout,
    );
    final toReleaseTag = release['tag_name'] as String;

    final work = differentialWorkDirectory();
    if (work.existsSync()) work.deleteSync(recursive: true);

    final service = DifferentialUpdateService(
      installRoot: installRoot,
      workRoot: work,
      architecture: architecture,
      installedReleaseTag: installedReleaseTag,
      download: (url, target, {int? expectedSize}) async {
        await downloadReleaseFile(
          target,
          url,
          'otzaria-small-update',
          expectedSize: expectedSize,
        );
        return target;
      },
    );
    return await service.prepare(toReleaseTag);
  }

  /// משגר את המעדכן העצמאי עם תוכנית ההחלפה, אחרי שהמשתמש אישר את סגירת
  /// אוצריא. מחזיר `true` רק אם התהליך נוצר בפועל.
  Future<bool> _launchDifferentialSwap({required bool relaunchApp}) async {
    final prepared = _differentialUpdate;
    if (prepared == null) return false;

    // בסגירת התוכנה המשתמש כבר הכריע לצאת — שאלה נוספת שם היא קפיצה
    // מיותרת בדרך החוצה.
    if (relaunchApp) {
      if (!mounted) return false;
      final confirmed = await showTwoActionsDialog(
        context: context,
        title: LibraryMessages.smallUpdateDialogTitle,
        content: LibraryMessages.smallUpdateDialogContent,
        cancelText: LibraryMessages.smallUpdateDialogCancel,
        confirmText: LibraryMessages.smallUpdateDialogConfirm,
      );
      if (confirmed != true) return false;
    }

    try {
      final staged = prepared.staged;
      if (staged.isTree) {
        await launchTreeSwap(
          installRoot: staged.installRoot,
          preparedRoot: staged.stagingRoot,
          workRoot: staged.workRoot,
          relaunchApp: relaunchApp,
        );
        return true;
      }
      final plan = await prepared.staged.writeSwapPlan(
        relaunchExecutable: relaunchApp ? Platform.resolvedExecutable : null,
        waitForPid: pid,
      );
      final helper = File(
        p.join(p.dirname(Platform.resolvedExecutable), 'otzaria_updater.exe'),
      );
      if (!launchWindowsDetachedProcess(
        helper.absolute.path,
        arguments: ['--plan', plan.absolute.path],
      )) {
        throw Exception('Failed to launch the updater helper');
      }
      return true;
    } catch (error, stackTrace) {
      debugPrint('[Update] small update launch failed: $error\n$stackTrace');
      _showUpdateError(LibraryMessages.updateInstallerLaunchError);
      return false;
    }
  }

  /// משגר את המתקין ומחזיר `true` אם השיגור הצליח. כשל בשיגור נבלע,
  /// מציג הודעת שגיאה רגילה ומחזיר `false`.
  ///
  /// [relaunchApp] — האם אוצריא תופעל מחדש בסיום ההתקנה (רלוונטי למתקין
  /// השקט ב-Windows): `true` בעדכון יזום ("התקן כעת"), `false` בעדכון
  /// בעת סגירת התוכנה.
  Future<bool> _launchInstaller({required bool relaunchApp}) =>
      _installerLaunch ??= _launchInstallerOnce(
        relaunchApp: relaunchApp,
      ).whenComplete(() => _installerLaunch = null);

  Future<bool> _launchInstallerOnce({required bool relaunchApp}) async {
    try {
      if (_differentialUpdate != null) {
        return await _launchDifferentialSwap(relaunchApp: relaunchApp);
      }
      if (_installerFile == null) return false;
      await _launchInstallerDirect(relaunchApp: relaunchApp);
      return true;
    } catch (_) {
      _showUpdateError(LibraryMessages.updateInstallerLaunchError);
      return false;
    }
  }

  Future<void> _launchInstallerDirect({required bool relaunchApp}) async {
    final installer = _installerFile;
    if (installer == null) return;

    // המתקין השקט נוצר ב-CreateProcess עם breakaway (ולא Process.start) כדי
    // שישרוד את סגירת אוצריא — ראה launchWindowsSilentInstaller.
    if (Platform.isWindows && _installerIsSilent) {
      if (!launchWindowsSilentInstaller(
        installerPath: installer.absolute.path,
        relaunchApp: relaunchApp,
      )) {
        throw Exception('Failed to launch the silent installer');
      }
      return;
    }

    // macOS: zip + bundle בר-החלפה = עדכון עצמי בסקריפט; אחרת openInstaller
    // מעגן (mount) את ה-DMG להתקנה ידנית בגרירה.
    if (Platform.isMacOS && installer.path.toLowerCase().endsWith('.zip')) {
      final appBundlePath = findInstalledMacAppBundlePath();
      if (appBundlePath != null) {
        await installMacUpdate(
          zipFile: installer,
          appBundlePath: appBundlePath,
          relaunchApp: relaunchApp,
        );
        return;
      }
    }

    // ב-Linux חבילות deb/rpm מותקנות בטרמינל עם pkexec והפעלה מחדש לפי
    // [relaunchApp]. אם אין מנהל חבילות נתמך — נופלים לפתיחת הקובץ
    // במתקין הגרפי של המערכת (ההתנהגות הקודמת).
    final lowerPath = installer.path.toLowerCase();
    if (Platform.isLinux &&
        (lowerPath.endsWith('.deb') || lowerPath.endsWith('.rpm'))) {
      try {
        await installLinuxUpdate(
          packageFile: installer,
          relaunchApp: relaunchApp,
        );
        return;
      } catch (_) {
        // נפילה ל-openInstaller למטה.
      }
    }

    if (Platform.isWindows && lowerPath.endsWith('.zip')) {
      await _launchWindowsPortableSwap(installer, relaunchApp: relaunchApp);
      return;
    }

    await openInstaller(installer, 'otzaria');
  }

  /// מחליף את קובצי התיקייה הניידת בקבצים שחולצו מה-zip, דרך המעדכן העצמאי
  /// ואחרי יציאת אוצריא — כמו העדכון המצומצם.
  Future<void> _launchWindowsPortableSwap(
    File zipFile, {
    required bool relaunchApp,
  }) async {
    final installRoot = Directory(p.dirname(Platform.resolvedExecutable));
    final work = differentialWorkDirectory();
    final plan = await fullPackageSwapPlan(
      installRoot: installRoot,
      stagingRoot: Directory(p.join(p.dirname(zipFile.path), 'otzaria')),
      backupRoot: Directory(p.join(work.path, kSwapBackupDirName)),
      platform: 'windows',
      architecture: installedWindowsArchitecture(
        isWindowsOnArm: WindowsArchInfo.isWindowsOnArm,
        isEmulatedOnArm: WindowsArchInfo.isEmulatedOnArm,
      ),
      fromReleaseTag: _currentVersion ?? 'unknown',
      toReleaseTag: _latestVersion ?? 'unknown',
      relaunchExecutable: relaunchApp ? Platform.resolvedExecutable : null,
      waitForPid: pid,
    );
    final planFile = await writeSwapPlanFile(plan, work);
    final helper = File(p.join(installRoot.path, kUpdaterHelperFileName));
    if (!launchWindowsDetachedProcess(
      helper.absolute.path,
      arguments: ['--plan', planFile.absolute.path],
    )) {
      throw Exception('Failed to launch the updater helper');
    }
  }

  /// בהתקנה ניידת ב-Windows העדכון מוחל במקום רק דרך המעדכן העצמאי.
  bool _canSwapWindowsPortable() {
    final installRoot = Directory(p.dirname(Platform.resolvedExecutable));
    return File(
          p.join(installRoot.path, kUpdaterHelperFileName),
        ).existsSync() &&
        isDirectoryWritable(installRoot);
  }

  void _dismissUpdate() {
    if (!mounted) return;
    setState(() {
      _status = UpdatStatus.dismissed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ManagedUpdateScope(
      latestVersion: _latestVersion,
      appVersion: _currentVersion ?? 'unknown',
      status: _status,
      changelog: _changelog,
      awaitingClose: _awaitingCloseForUpdate,
      checkForUpdate: _checkForUpdate,
      startUpdate: _startUpdate,
      launchInstaller: _installNow,
      dismissUpdate: _dismissUpdate,
      child: widget.child,
    );
  }
}

class ManagedUpdateScope extends InheritedWidget {
  const ManagedUpdateScope({
    super.key,
    required this.latestVersion,
    required this.appVersion,
    required this.status,
    required this.changelog,
    this.awaitingClose = false,
    required this.checkForUpdate,
    required this.startUpdate,
    required this.launchInstaller,
    required this.dismissUpdate,
    required super.child,
  });

  final String? latestVersion;
  final String appVersion;
  final UpdatStatus status;
  final String? changelog;

  /// ההתקנה החלה והתהליך עוד חי — ראה `_awaitingCloseForUpdate`.
  final bool awaitingClose;
  final VoidCallback checkForUpdate;
  final VoidCallback startUpdate;
  final Future<void> Function() launchInstaller;
  final VoidCallback dismissUpdate;

  static ManagedUpdateScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ManagedUpdateScope>();
  }

  @override
  bool updateShouldNotify(ManagedUpdateScope oldWidget) {
    return latestVersion != oldWidget.latestVersion ||
        appVersion != oldWidget.appVersion ||
        status != oldWidget.status ||
        changelog != oldWidget.changelog ||
        awaitingClose != oldWidget.awaitingClose;
  }
}

class ManagedUpdateTitleBarIndicator extends StatelessWidget {
  const ManagedUpdateTitleBarIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final update = ManagedUpdateScope.maybeOf(context);
    if (update == null) return const SizedBox.shrink();

    void openDialog() {
      hebrewDefaultDialog(
        context: context,
        latestVersion: update.latestVersion,
        appVersion: update.appVersion,
        status: update.status,
        changelog: update.changelog,
        checkForUpdate: update.checkForUpdate,
        openDialog: () {},
        startUpdate: update.startUpdate,
        launchInstaller: update.launchInstaller,
        dismissUpdate: update.dismissUpdate,
      );
    }

    return hebrewFlatChip(
      context: context,
      awaitingClose: update.awaitingClose,
      latestVersion: update.latestVersion,
      appVersion: update.appVersion,
      status: update.status,
      checkForUpdate: update.checkForUpdate,
      openDialog: openDialog,
      startUpdate: update.startUpdate,
      launchInstaller: update.launchInstaller,
      dismissUpdate: update.dismissUpdate,
    );
  }
}

/// מוריד את קובץ העדכון מ-[url] אל [file] (ומחלץ zip מחוץ ל-macOS).
///
/// אין חסם על משך ההורדה הכולל — הורדה איטית שמתקדמת אינה נכשלת. הכשל הוא
/// רק על חיבור שלא נענה תוך [connectTimeout] או על זרם שלא הזרים בייטים
/// במשך [stallTimeout]; בשני המקרים החיבור נסגר ולא נשאר תלוי.
///
/// הכתיבה היא לקובץ זמני ששמו מוחלף רק אחרי שהגודל אומת מול [expectedSize]:
/// הורדה שנקטעה לא תיראה כקובץ שלם בניסיון הבא.
@visibleForTesting
Future<File> downloadReleaseFile(
  File file,
  String url,
  String appName, {
  Duration connectTimeout = _kDownloadConnectTimeout,
  Duration stallTimeout = _kDownloadStallTimeout,
  int? expectedSize,
}) async {
  final client = http.Client();
  final partial = File('${file.path}.part');
  IOSink? sink;
  try {
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request).timeout(connectTimeout);
    if (response.statusCode != 200) {
      throw Exception('Download failed with status ${response.statusCode}');
    }

    await file.parent.create(recursive: true);
    sink = partial.openWrite();

    await for (final chunk in response.stream.timeout(stallTimeout)) {
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
    sink = null;

    final downloaded = await partial.length();
    if (expectedSize != null &&
        expectedSize > 0 &&
        downloaded != expectedSize) {
      throw Exception(
        'Download is $downloaded bytes but $expectedSize were expected',
      );
    }
    if (await file.exists()) await file.delete();
    await partial.rename(file.path);

    // ב-macOS אין לחלץ את ה-zip ב-Dart: חבילת archive אינה משמרת symlinks
    // והרשאות הפעלה שבתוך ה-bundle. סקריפט העדכון מחלץ בעצמו עם ditto.
    if (file.path.toLowerCase().endsWith('.zip') && !Platform.isMacOS) {
      final outDir = Directory(p.join(p.dirname(file.path), appName));
      if (outDir.existsSync()) {
        outDir.deleteSync(recursive: true);
      }
      outDir.createSync(recursive: true);
      await extractArchiveFileToDisk(
        file.absolute.path,
        outDir.absolute.path,
      );
    }

    return file;
  } finally {
    await sink?.close();
    client.close();
    if (partial.existsSync()) {
      try {
        partial.deleteSync();
      } catch (_) {
        // שארית ב-temp אינה מצדיקה כישלון נוסף על זה שכבר נזרק.
      }
    }
  }
}

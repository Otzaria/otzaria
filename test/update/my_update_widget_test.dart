import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/update/my_update_widget.dart';
import 'package:otzaria/update/updat_compat.dart';

void main() {
  group('InitialSoftwareCheck', () {
    test('RestartWidget: בדיקה חדשה אינה יורשת תוצאה מהפעלה קודמת', () async {
      final check = InitialSoftwareCheck();
      final first = check.begin();
      check.resolve(first, updateAvailable: true);
      expect(await check.result, isTrue);

      final second = check.begin();
      var secondSettled = false;
      check.result.then((_) => secondSettled = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondSettled, isFalse);
      check.resolve(second, updateAvailable: false);
      expect(await check.result, isFalse);
    });

    test('סיום מאוחר של בדיקה ישנה לא משנה בדיקה חדשה', () async {
      final check = InitialSoftwareCheck();
      final first = check.begin();
      final oldResult = check.result;
      final second = check.begin();
      check.resolve(first, updateAvailable: true);
      expect(await oldResult, isFalse);
      check.resolve(second, updateAvailable: true);
      expect(await check.result, isTrue);
    });
  });

  group('supportsManagedUpdatePlatform', () {
    test('supports desktop platforms only', () {
      expect(
        supportsManagedUpdatePlatform(
          isWeb: false,
          operatingSystem: 'windows',
        ),
        isTrue,
      );
      expect(
        supportsManagedUpdatePlatform(
          isWeb: false,
          operatingSystem: 'macos',
        ),
        isTrue,
      );
      expect(
        supportsManagedUpdatePlatform(
          isWeb: false,
          operatingSystem: 'linux',
        ),
        isTrue,
      );
      expect(
        supportsManagedUpdatePlatform(
          isWeb: false,
          operatingSystem: 'android',
        ),
        isFalse,
      );
      expect(
        supportsManagedUpdatePlatform(
          isWeb: false,
          operatingSystem: 'ios',
        ),
        isFalse,
      );
      expect(
        supportsManagedUpdatePlatform(
          isWeb: true,
          operatingSystem: 'windows',
        ),
        isFalse,
      );
    });
  });

  group('managesUpdatesInThisWindow', () {
    // ⚠️ רגרסיה (#1188, #1190): ה-hook שהעוטף מתקין קרא ל-quitApplication
    // בכל סגירה והפיל את התהליך — ב-release בלבד, כי ב-debug הוא מדולג.
    bool manages({
      bool isDebug = false,
      bool isSecondaryWindow = false,
      bool isWeb = false,
      String operatingSystem = 'windows',
    }) => managesUpdatesInThisWindow(
      isDebug: isDebug,
      isSecondaryWindow: isSecondaryWindow,
      isWeb: isWeb,
      operatingSystem: operatingSystem,
    );

    test('חלון ראשי ב-release על שולחן עבודה — מנהל', () {
      expect(manages(), isTrue);
      expect(manages(operatingSystem: 'macos'), isTrue);
      expect(manages(operatingSystem: 'linux'), isTrue);
    });

    test('חלון משני אינו מנהל — בדיקה, הורדה והתקנה הן פר-תהליך', () {
      expect(manages(isSecondaryWindow: true), isFalse);
      expect(
        manages(isSecondaryWindow: true, operatingSystem: 'macos'),
        isFalse,
      );
    });

    test('ב-debug אין ניהול — ולכן מה שהעוטף מתקין קיים ב-release בלבד', () {
      expect(manages(isDebug: true), isFalse);
      expect(manages(isDebug: true, isSecondaryWindow: true), isFalse);
    });

    test('פלטפורמה שאינה נתמכת אינה מנהלת', () {
      expect(manages(operatingSystem: 'android'), isFalse);
      expect(manages(operatingSystem: 'ios'), isFalse);
      expect(manages(isWeb: true), isFalse);
    });
  });

  group('managesUpdatesHere', () {
    tearDown(() => ProcessDuties.debugOverride = null);

    final supported = supportsManagedUpdatePlatform(
      isWeb: false,
      operatingSystem: Platform.operatingSystem,
    );

    test('לא-בעלים של התהליך אינו מנהל', () {
      final notOwner = ProcessDuties(isProcessOwner: () => false);
      expect(managesUpdatesHere(isDebug: false, duties: notOwner), isFalse);
      ProcessDuties.debugOverride = notOwner;
      expect(managesUpdatesHere(isDebug: false), isFalse);
    });

    test('בעלים מנהל בפלטפורמה נתמכת', () {
      final owner = ProcessDuties(isProcessOwner: () => true);
      expect(managesUpdatesHere(isDebug: false, duties: owner), supported);
      ProcessDuties.debugOverride = owner;
      expect(managesUpdatesHere(isDebug: false), supported);
    });
  });

  group('updateCheckBlocked', () {
    // מצב מנותק חוסם את *בדיקת* העדכון בלבד — אסור שישנה את צורת עץ
    // הווידג'טים, אחרת ה-PageView הראשי נבנה מחדש ומציג מסך שגוי.
    test('blocked when offline or when updates are disabled', () {
      expect(
        updateCheckBlocked(isOfflineMode: true, updatesEnabled: true),
        isTrue,
      );
      expect(
        updateCheckBlocked(isOfflineMode: false, updatesEnabled: false),
        isTrue,
      );
      expect(
        updateCheckBlocked(isOfflineMode: true, updatesEnabled: false),
        isTrue,
      );
      expect(
        updateCheckBlocked(isOfflineMode: false, updatesEnabled: true),
        isFalse,
      );
    });
  });

  group('updateCheckFailureMessage', () {
    // שרת עדכונים לא נגיש (אין רשת, או רשת מסוננת שחוסמת אותו) אינו תקלה
    // לדווח עליה — הודעה כזו בפתיחת התוכנה היא רעש שאין לו מענה (issue #1027).
    test('שרת לא נגיש — אין הודעה כלל, גם לכשל רשת וגם לכשל אחר', () {
      expect(
        updateCheckFailureMessage(
          isNetworkError: true,
          isSourceReachable: false,
        ),
        isNull,
      );
      expect(
        updateCheckFailureMessage(
          isNetworkError: false,
          isSourceReachable: false,
        ),
        isNull,
      );
    });

    test('שרת נגיש — כשל רשת מקבל את הודעת הרשת', () {
      expect(
        updateCheckFailureMessage(
          isNetworkError: true,
          isSourceReachable: true,
        ),
        LibraryMessages.updateCheckNetworkError,
      );
    });

    test('שרת נגיש — כשל שאינו רשת מקבל את ההודעה הכללית', () {
      expect(
        updateCheckFailureMessage(
          isNetworkError: false,
          isSourceReachable: true,
        ),
        LibraryMessages.updateCheckError,
      );
    });
  });

  group('offlineRecheckDelay', () {
    test('שלושה ניסיונות בהשהיות עולות, ואז די', () {
      expect(offlineRecheckDelay(0), const Duration(minutes: 2));
      expect(offlineRecheckDelay(1), const Duration(minutes: 5));
      expect(offlineRecheckDelay(2), const Duration(minutes: 15));
      expect(offlineRecheckDelay(3), isNull);
      expect(offlineRecheckDelay(50), isNull);
    });

    test('ההשהיה תמיד עולה — אין הצפת בדיקות רשת', () {
      var previous = Duration.zero;
      for (var attempt = 0; offlineRecheckDelay(attempt) != null; attempt++) {
        final delay = offlineRecheckDelay(attempt)!;
        expect(delay, greaterThan(previous));
        previous = delay;
      }
    });

    test('הניסיון הראשון אינו מיידי — חיבור לא חוזר תוך שניות', () {
      expect(
        offlineRecheckDelay(0)!.inMinutes,
        greaterThanOrEqualTo(1),
        reason: 'ניסיון מיידי היה מבזבז רשת בלי סיכוי אמיתי להצליח',
      );
    });
  });

  group('shouldRecheckAfterUnblock', () {
    // חסימה קובעת upToDate בלי בדיקה אמיתית — מעבר מחסימה לזמינות חייב
    // להפעיל בדיקה מחדש, בלי לקטוע הורדה/התקנה שכבר בעיצומן.
    test('rechecks only on blocked-to-unblocked transition while upToDate', () {
      expect(
        shouldRecheckAfterUnblock(
          wasBlocked: true,
          isBlocked: false,
          status: UpdatStatus.upToDate,
        ),
        isTrue,
      );
      expect(
        shouldRecheckAfterUnblock(
          wasBlocked: false,
          isBlocked: false,
          status: UpdatStatus.upToDate,
        ),
        isFalse,
      );
      expect(
        shouldRecheckAfterUnblock(
          wasBlocked: true,
          isBlocked: true,
          status: UpdatStatus.upToDate,
        ),
        isFalse,
      );
    });

    test('does not interrupt an active download or a found update', () {
      for (final status in [
        UpdatStatus.checking,
        UpdatStatus.availableWithChangelog,
        UpdatStatus.downloading,
        UpdatStatus.readyToInstall,
        UpdatStatus.dismissed,
      ]) {
        expect(
          shouldRecheckAfterUnblock(
            wasBlocked: true,
            isBlocked: false,
            status: status,
          ),
          isFalse,
        );
      }
    });
  });

  group('shouldLaunchInstallerOnExit', () {
    test('requires installer file and a completed download state', () {
      expect(
        shouldLaunchInstallerOnExit(
          status: UpdatStatus.readyToInstall,
          hasInstallerFile: true,
        ),
        isTrue,
      );
      expect(
        shouldLaunchInstallerOnExit(
          status: UpdatStatus.dismissed,
          hasInstallerFile: true,
        ),
        isTrue,
      );
      expect(
        shouldLaunchInstallerOnExit(
          status: UpdatStatus.downloading,
          hasInstallerFile: true,
        ),
        isFalse,
      );
      expect(
        shouldLaunchInstallerOnExit(
          status: UpdatStatus.readyToInstall,
          hasInstallerFile: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldDestroyWindowAfterInstallNow', () {
    // רגרסיה לתקלה מהפורום (topic 1530): לפני התיקון "התקן עכשיו" נתקע
    // לנצח כי אוצריא נסגרה/נשארה פתוחה בלי קשר להצלחת שיגור המתקין.
    test('closes the window only when the installer actually launched', () {
      expect(
        shouldDestroyWindowAfterInstallNow(installerLaunched: true),
        isTrue,
      );
      expect(
        shouldDestroyWindowAfterInstallNow(installerLaunched: false),
        isFalse,
      );
    });
  });

  group('pickWindowsAssetUrl', () {
    Map<String, dynamic> asset(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
    };

    // נכסי release מציאותיים, כפי שמועלים ע"י build-and-announce.yml.
    final fullReleaseAssets = [
      // הסמלים קודמים לחבילות בסדר ההעלאה, ואסור שייבחרו כחבילה ניידת.
      asset('otzaria-native-symbols-arm64.zip'),
      asset('otzaria-native-symbols-x64.zip'),
      asset('otzaria-0.9.96-windows.exe'),
      asset('otzaria-0.9.96-windows_arm64.exe'),
      asset('otzaria-0.9.96-windows-full.exe'),
      asset('otzaria-windows.zip'),
      asset('otzaria-windows_arm64.zip'),
      asset('otzaria-0.9.96-linux.deb'),
      asset('otzaria-macos.dmg'),
    ];

    test('picks the installer for exe installs', () {
      expect(
        pickWindowsAssetUrl(
          fullReleaseAssets,
          preferredFormat: 'exe',
          isArmMachine: false,
        ),
        'https://example.com/otzaria-0.9.96-windows.exe',
      );
    });

    test('never selects full installers', () {
      final assets = [
        asset('otzaria-0.9.96-windows-full.exe'),
      ];
      expect(
        pickWindowsAssetUrl(
          assets,
          preferredFormat: 'exe',
          isArmMachine: false,
        ),
        isNull,
      );
    });

    test('prefers zip for portable installs with exe as fallback', () {
      expect(
        pickWindowsAssetUrl(
          fullReleaseAssets,
          preferredFormat: 'zip',
          isArmMachine: false,
        ),
        'https://example.com/otzaria-windows.zip',
      );

      final withoutZip = [
        asset('otzaria-0.9.96-windows.exe'),
      ];
      expect(
        pickWindowsAssetUrl(
          withoutZip,
          preferredFormat: 'zip',
          isArmMachine: false,
        ),
        'https://example.com/otzaria-0.9.96-windows.exe',
      );
    });

    test('ignores assets of other platforms', () {
      final assets = [
        asset('otzaria-0.9.94-linux.deb'),
        asset('otzaria-macos.dmg'),
        asset('otzaria-macos.zip'),
      ];
      expect(
        pickWindowsAssetUrl(
          assets,
          preferredFormat: 'exe',
          isArmMachine: false,
        ),
        isNull,
      );
    });

    test('an x64 machine never receives an arm64 asset', () {
      final assets = [
        asset('otzaria-0.9.97-windows_arm64.exe'),
        asset('otzaria-windows_arm64.zip'),
      ];
      expect(
        pickWindowsAssetUrl(
          assets,
          preferredFormat: 'exe',
          isArmMachine: false,
        ),
        isNull,
      );
    });

    // גרסאות עד 0.9.96 בוחרות את הנכס הראשון שאינו full, ו-GitHub מחזיר
    // את הנכסים ממוינים לפי שם — נכס ה-ARM חייב להיות ממוין אחרי ה-x64.
    test('legacy first-match pickers still receive the x64 assets', () {
      String? legacyPick(String extension) {
        final names = fullReleaseAssets.map((a) => a['name'] as String).toList()
          ..sort();
        return names.firstWhere(
          (n) =>
              n.contains('win') && !n.contains('full') && n.endsWith(extension),
        );
      }

      expect(legacyPick('.exe'), 'otzaria-0.9.96-windows.exe');
      expect(legacyPick('.zip'), 'otzaria-windows.zip');
    });

    test('an ARM machine prefers the arm64 installer', () {
      expect(
        pickWindowsAssetUrl(
          fullReleaseAssets,
          preferredFormat: 'exe',
          isArmMachine: true,
        ),
        'https://example.com/otzaria-0.9.96-windows_arm64.exe',
      );
      expect(
        pickWindowsAssetUrl(
          fullReleaseAssets,
          preferredFormat: 'zip',
          isArmMachine: true,
        ),
        'https://example.com/otzaria-windows_arm64.zip',
      );
    });

    test('an ARM machine falls back to x64 when no arm64 asset exists', () {
      final withoutArm = [
        asset('otzaria-0.9.96-windows.exe'),
        asset('otzaria-windows.zip'),
      ];
      expect(
        pickWindowsAssetUrl(
          withoutArm,
          preferredFormat: 'exe',
          isArmMachine: true,
        ),
        'https://example.com/otzaria-0.9.96-windows.exe',
      );
    });

    test('never selects the download assistant', () {
      final withAssistant = [
        ...fullReleaseAssets,
        asset('Otzaria-Download-Assistant-windows.exe'),
      ];
      expect(
        pickWindowsAssetUrl(
          withAssistant,
          preferredFormat: 'exe',
          isArmMachine: false,
        ),
        'https://example.com/otzaria-0.9.96-windows.exe',
      );
      expect(
        pickWindowsAssetUrl(
          withAssistant,
          preferredFormat: 'exe',
          isArmMachine: true,
        ),
        'https://example.com/otzaria-0.9.96-windows_arm64.exe',
      );
    });

    test('the download assistant is not chosen even as the only exe', () {
      // גם השם הישן: שחרורים שכבר פורסמו נושאים אותו, והמעדכן חייב
      // להמשיך לדלג עליהם.
      for (final name in const [
        'Otzaria-Download-Assistant-windows.exe',
        'Otzaria-Download-Assistant-win.exe',
        'otzaria_download_assistant_win.exe',
      ]) {
        expect(
          pickWindowsAssetUrl(
            [asset(name)],
            preferredFormat: 'exe',
            isArmMachine: false,
          ),
          isNull,
          reason: name,
        );
        expect(
          pickWindowsAssetUrl(
            [asset(name)],
            preferredFormat: 'zip',
            isArmMachine: true,
          ),
          isNull,
          reason: name,
        );
      }
    });

    test('differential update packages are never picked as the zip', () {
      final assets = [
        asset('otzaria-update-windows-x64-0.10.2_142-to-0.10.3_143.zip'),
        asset('otzaria-update-windows-arm64-0.10.2_142-to-0.10.3_143.zip'),
        asset('otzaria-windows.zip'),
        asset('otzaria-windows_arm64.zip'),
      ];
      expect(
        pickWindowsAssetUrl(
          assets,
          preferredFormat: 'zip',
          isArmMachine: false,
        ),
        'https://example.com/otzaria-windows.zip',
      );
      expect(
        pickWindowsAssetUrl(assets, preferredFormat: 'zip', isArmMachine: true),
        'https://example.com/otzaria-windows_arm64.zip',
      );
    });

    test('isDownloadAssistantAsset matches only the assistant', () {
      expect(
        isDownloadAssistantAsset('Otzaria-Download-Assistant-windows.exe'),
        isTrue,
      );
      expect(
        isDownloadAssistantAsset('Otzaria-Download-Assistant-win.exe'),
        isTrue,
      );
      expect(isDownloadAssistantAsset('otzaria-0.9.97-windows.exe'), isFalse);
      expect(
        isDownloadAssistantAsset('otzaria-0.9.97-windows-full-indexed.exe'),
        isFalse,
      );
    });
  });

  group('pickMacAssetUrl', () {
    Map<String, dynamic> asset(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
    };

    final fullReleaseAssets = [
      asset('otzaria-0.9.94-windows.exe'),
      asset('otzaria-windows.zip'),
      asset('otzaria-macos.dmg'),
      asset('otzaria-macos.zip'),
      asset('otzaria-macos-full.tar.zst'),
      asset('otzaria-0.9.94-linux.deb'),
    ];

    test('prefers the app zip when self-update is possible', () {
      expect(
        pickMacAssetUrl(fullReleaseAssets, selfUpdateCapable: true),
        'https://example.com/otzaria-macos.zip',
      );
    });

    test('prefers the dmg when self-update is not possible', () {
      expect(
        pickMacAssetUrl(fullReleaseAssets, selfUpdateCapable: false),
        'https://example.com/otzaria-macos.dmg',
      );
    });

    test('falls back to dmg on old releases without an update zip', () {
      final oldRelease = [
        asset('otzaria-macos.dmg'),
        asset('otzaria-macos-full.tar.zst'),
      ];
      expect(
        pickMacAssetUrl(oldRelease, selfUpdateCapable: true),
        'https://example.com/otzaria-macos.dmg',
      );
    });

    test('never selects full bundles', () {
      final assets = [asset('otzaria-macos-full.tar.zst')];
      expect(pickMacAssetUrl(assets, selfUpdateCapable: true), isNull);
      expect(pickMacAssetUrl(assets, selfUpdateCapable: false), isNull);
    });

    test('without self-update returns only dmg — zip alone is unusable', () {
      // zip ללא עדכון עצמי אינו מחולץ ב-Dart ולכן openInstaller נכשל עליו;
      // עדיף null (צ'יפ שגיאה) מאשר כשל באמצע התקנה.
      final zipOnly = [asset('otzaria-macos.zip')];
      expect(pickMacAssetUrl(zipOnly, selfUpdateCapable: false), isNull);
    });

    test('never selects the macOS download assistant', () {
      // שם המסייע מכיל "macos" ומסתיים ב-zip; הוא ממוין לפני otzaria-macos.zip.
      final withAssistant = [
        asset('Otzaria-Download-Assistant-macos.zip'),
        ...fullReleaseAssets,
      ];
      expect(
        pickMacAssetUrl(withAssistant, selfUpdateCapable: true),
        'https://example.com/otzaria-macos.zip',
      );
      expect(
        pickMacAssetUrl([
          asset('Otzaria-Download-Assistant-macos.zip'),
        ], selfUpdateCapable: true),
        isNull,
      );
    });
  });

  group('pickLinuxAssetUrl', () {
    Map<String, dynamic> asset(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
    };

    test('DEB first, then RPM, then a Linux zip', () {
      expect(
        pickLinuxAssetUrl([
          asset('otzaria-0.9.97+789-789.x86_64.rpm'),
          asset('otzaria-0.9.97+789-linux.deb'),
        ], isArm64: false),
        'https://example.com/otzaria-0.9.97+789-linux.deb',
      );
      expect(
        pickLinuxAssetUrl([
          asset('otzaria-linux-raw.zip'),
          asset('otzaria-0.9.97+789-789.x86_64.rpm'),
        ], isArm64: false),
        'https://example.com/otzaria-0.9.97+789-789.x86_64.rpm',
      );
      expect(
        pickLinuxAssetUrl([
          asset('otzaria-windows.zip'),
          asset('otzaria-linux-raw.zip'),
        ], isArm64: false),
        'https://example.com/otzaria-linux-raw.zip',
      );
    });

    // סדר הנכסים כפי ש-GitHub מחזיר אותו ב-release 0.9.97+789 — ה-arm64
    // לפני ה-x64 גם ב-deb וגם ב-rpm.
    final release09797 = [
      for (final name in const [
        'app-release.apk',
        'assemble_split_asset.ps1',
        'assemble_split_asset.sh',
        'otzaria-0.9.97+99702-99702.aarch64.rpm',
        'otzaria-0.9.97+99702-99702.x86_64.rpm',
        'otzaria-0.9.97+99702-linux-arm64.deb',
        'otzaria-0.9.97+99702-linux.deb',
        'otzaria-0.9.97-library-full-indexed.tar.zst.manifest.json',
        'otzaria-0.9.97-windows-full-indexed.exe',
        'otzaria-0.9.97-windows-full.exe',
        'otzaria-0.9.97-windows.exe',
        'otzaria-0.9.97-windows_arm64.exe',
        'otzaria-android-full.zip',
        'otzaria-linux-full-arm64.tar.zst',
        'otzaria-linux-full.tar.zst',
        'otzaria-macos-full.tar.zst',
        'otzaria-macos.dmg',
        'otzaria-macos.zip',
        'otzaria-windows.zip',
        'otzaria-windows_arm64.zip',
      ])
        asset(name),
    ];

    test('x64 never gets the arm64 package from the real 0.9.97 release', () {
      expect(
        pickLinuxAssetUrl(release09797, isArm64: false),
        'https://example.com/otzaria-0.9.97+99702-linux.deb',
      );
      final withoutDeb = release09797
          .where((a) => !(a['name'] as String).endsWith('.deb'))
          .toList();
      expect(
        pickLinuxAssetUrl(withoutDeb, isArm64: false),
        'https://example.com/otzaria-0.9.97+99702-99702.x86_64.rpm',
      );
    });

    test('arm64 gets the arm64 package, and never an x64 one', () {
      expect(
        pickLinuxAssetUrl(release09797, isArm64: true),
        'https://example.com/otzaria-0.9.97+99702-linux-arm64.deb',
      );
      final withoutDeb = release09797
          .where((a) => !(a['name'] as String).endsWith('.deb'))
          .toList();
      expect(
        pickLinuxAssetUrl(withoutDeb, isArm64: true),
        'https://example.com/otzaria-0.9.97+99702-99702.aarch64.rpm',
      );
      // x64 בלבד — עדיף בלי עדכון מאשר חבילה שלא תותקן.
      expect(
        pickLinuxAssetUrl([
          asset('otzaria-0.9.97+99702-linux.deb'),
          asset('otzaria-0.9.97+99702-99702.x86_64.rpm'),
        ], isArm64: true),
        isNull,
      );
    });

    test('never selects the Linux download assistant', () {
      for (final name in const [
        'Otzaria-Download-Assistant-linux-x64.tar.gz',
        'Otzaria-Download-Assistant-linux-arm64.tar.gz',
        // גם אם ייארז יום אחד כ-zip או כ-deb, הוא אינו עדכון.
        'Otzaria-Download-Assistant-linux-x64.zip',
        'Otzaria-Download-Assistant-linux-x64.deb',
        'Otzaria-Download-Assistant-linux-arm64.deb',
      ]) {
        for (final isArm64 in const [false, true]) {
          expect(
            pickLinuxAssetUrl([asset(name)], isArm64: isArm64),
            isNull,
            reason: '$name (arm64: $isArm64)',
          );
        }
      }
    });
  });

  group('preferredWindowsFormatForInstall', () {
    test('installed app (admin or per-user) uses the exe installer', () {
      expect(
        preferredWindowsFormatForInstall(isInstalledApp: true),
        'exe',
      );
    });

    test('portable mode (portable.marker present) uses the zip', () {
      expect(
        preferredWindowsFormatForInstall(isInstalledApp: false),
        'zip',
      );
    });
  });

  group('isSilentWindowsInstallerUrl', () {
    test('treats every exe installer as silent-capable, zip is not', () {
      expect(
        isSilentWindowsInstallerUrl(
          'https://github.com/Otzaria/otzaria/releases/download/0.9.96/otzaria-0.9.96-windows.exe',
        ),
        isTrue,
      );
      expect(
        isSilentWindowsInstallerUrl(
          'https://github.com/Otzaria/otzaria/releases/download/0.9.96/otzaria-windows.zip',
        ),
        isFalse,
      );
    });
  });

  group('prepareUpdateInstallerFile', () {
    tearDown(() {
      final dir = updateWorkingDirectory();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test(
      'downloads into a private temp folder, not the user Downloads',
      () async {
        final file = await prepareUpdateInstallerFile(
          version: '0.9.96',
          extension: 'exe',
        );

        expect(p.basename(file.path), 'otzaria-0.9.96.exe');
        expect(p.dirname(file.path), updateWorkingDirectory().path);
        expect(file.path.toLowerCase(), isNot(contains('downloads')));
      },
    );

    test('clears leftovers from a previous download', () async {
      final dir = updateWorkingDirectory();
      dir.createSync(recursive: true);
      final stale = File(p.join(dir.path, 'otzaria-0.9.95.exe'))
        ..writeAsStringSync('stale');
      final staleExtract = Directory(p.join(dir.path, 'otzaria'))
        ..createSync(recursive: true);

      await prepareUpdateInstallerFile(version: '0.9.96', extension: 'exe');

      expect(stale.existsSync(), isFalse);
      expect(staleExtract.existsSync(), isFalse);
      expect(dir.existsSync(), isTrue);
    });
  });
}

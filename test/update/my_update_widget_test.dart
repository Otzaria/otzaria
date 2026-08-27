import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/update/my_update_widget.dart';
import 'package:updat/updat.dart';

void main() {
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
    // בלי אינטרנט אין תקלה לדווח עליה — הודעה כזו בפתיחת התוכנה היא רעש
    // שהמשתמש אינו יכול לעשות איתו דבר.
    test('בלי אינטרנט אין הודעה כלל — גם לכשל רשת וגם לכשל אחר', () {
      expect(
        updateCheckFailureMessage(isNetworkError: true, hasInternet: false),
        isNull,
      );
      expect(
        updateCheckFailureMessage(isNetworkError: false, hasInternet: false),
        isNull,
      );
    });

    test('עם אינטרנט — כשל רשת מקבל את הודעת הרשת', () {
      expect(
        updateCheckFailureMessage(isNetworkError: true, hasInternet: true),
        LibraryMessages.updateCheckNetworkError,
      );
    });

    test('עם אינטרנט — כשל שאינו רשת מקבל את ההודעה הכללית', () {
      expect(
        updateCheckFailureMessage(isNetworkError: false, hasInternet: true),
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

  group('pickPreferredReleaseForDevChannel', () {
    test('selects stable when stable core version is newer than dev', () {
      final selected = pickPreferredReleaseForDevChannel(
        stableRelease: {'tag_name': '0.9.93+674'},
        devRelease: {'tag_name': '0.9.92+631'},
      );

      expect(selected['tag_name'], '0.9.93+674');
    });

    test('selects dev when dev core version is newer than stable', () {
      final selected = pickPreferredReleaseForDevChannel(
        stableRelease: {'tag_name': '0.9.93+674'},
        devRelease: {'tag_name': '0.9.94+10'},
      );

      expect(selected['tag_name'], '0.9.94+10');
    });

    test('selects stable release metadata when core versions are equal', () {
      final selected = pickPreferredReleaseForDevChannel(
        stableRelease: {'tag_name': '0.9.92'},
        devRelease: {'tag_name': '0.9.92+631'},
      );

      expect(selected['tag_name'], '0.9.92');
    });
  });

  group('pickWindowsAssetUrl', () {
    Map<String, dynamic> asset(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
    };

    // נכסי release מציאותיים, כפי שמועלים ע"י build-and-announce.yml.
    final fullReleaseAssets = [
      asset('otzaria-0.9.96-windows.exe'),
      asset('otzaria-0.9.96-windows-arm64.exe'),
      asset('otzaria-0.9.96-windows-full.exe'),
      asset('otzaria-windows.zip'),
      asset('otzaria-windows-arm64.zip'),
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
        asset('otzaria-0.9.97-windows-arm64.exe'),
        asset('otzaria-windows-arm64.zip'),
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

    test('an ARM machine prefers the arm64 installer', () {
      expect(
        pickWindowsAssetUrl(
          fullReleaseAssets,
          preferredFormat: 'exe',
          isArmMachine: true,
        ),
        'https://example.com/otzaria-0.9.96-windows-arm64.exe',
      );
      expect(
        pickWindowsAssetUrl(
          fullReleaseAssets,
          preferredFormat: 'zip',
          isArmMachine: true,
        ),
        'https://example.com/otzaria-windows-arm64.zip',
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
      asset('otzaria-macos-full.zip'),
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
        asset('otzaria-macos-full.zip'),
      ];
      expect(
        pickMacAssetUrl(oldRelease, selfUpdateCapable: true),
        'https://example.com/otzaria-macos.dmg',
      );
    });

    test('never selects full bundles', () {
      final assets = [asset('otzaria-macos-full.zip')];
      expect(pickMacAssetUrl(assets, selfUpdateCapable: true), isNull);
      expect(pickMacAssetUrl(assets, selfUpdateCapable: false), isNull);
    });

    test('without self-update returns only dmg — zip alone is unusable', () {
      // zip ללא עדכון עצמי אינו מחולץ ב-Dart ולכן openInstaller נכשל עליו;
      // עדיף null (צ'יפ שגיאה) מאשר כשל באמצע התקנה.
      final zipOnly = [asset('otzaria-macos.zip')];
      expect(pickMacAssetUrl(zipOnly, selfUpdateCapable: false), isNull);
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

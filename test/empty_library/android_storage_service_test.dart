import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/empty_library/services/android_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('listStorageOptions מחזיר ריק בפלטפורמה שאינה Android', () async {
    // הבדיקה רצה על מארח שאינו Android — אין ברירת מיקום ולכן הרשימה ריקה.
    if (Platform.isAndroid) return;
    final options = await AndroidStorageService.listStorageOptions();
    expect(options, isEmpty);
  });

  group('removableStoragePaths', () {
    test('מסיר את האחסון הראשי ושומר את כל הנפחים המשניים', () {
      expect(
        AndroidStorageService.removableStoragePaths(
          ['/storage/emulated/0', '/storage/SD-1', '/storage/USB-1'],
          primaryPath: '/storage/emulated/0',
        ),
        ['/storage/SD-1', '/storage/USB-1'],
      );
    });

    test('שומר את הנתיבים הזמינים כשהאחסון הראשי אינו זמין', () {
      expect(
        AndroidStorageService.removableStoragePaths(
          ['/storage/SD-1'],
          primaryPath: null,
        ),
        ['/storage/SD-1'],
      );
    });
  });

  group('largeFileSupportFromMounts', () {
    const sdPath = '/storage/ABCD-1234/Android/data/pkg/files';

    test('כרטיס vfat (FAT32) — לא תומך', () {
      const mounts =
          '/dev/block/vold/public:179,65 /mnt/media_rw/ABCD-1234 '
          'vfat rw,dirsync,nosuid 0 0\n'
          '/dev/fuse /storage/ABCD-1234 fuse rw,nosuid,nodev 0 0\n';
      expect(
        AndroidStorageService.largeFileSupportFromMounts(mounts, sdPath),
        isFalse,
      );
    });

    test('כרטיס exfat — תומך', () {
      const mounts =
          '/dev/block/vold/public:179,65 /mnt/media_rw/ABCD-1234 '
          'exfat rw,dirsync,nosuid 0 0\n';
      expect(
        AndroidStorageService.largeFileSupportFromMounts(mounts, sdPath),
        isTrue,
      );
    });

    test('נראית רק שכבת ה-FUSE — לא ניתן לקבוע (null)', () {
      const mounts = '/dev/fuse /storage/ABCD-1234 fuse rw,nosuid,nodev 0 0\n';
      expect(
        AndroidStorageService.largeFileSupportFromMounts(mounts, sdPath),
        isNull,
      );
    });

    test('הכרך אינו מופיע ב-mounts — לא ניתן לקבוע (null)', () {
      const mounts = '/dev/block/dm-0 /data ext4 rw 0 0\n';
      expect(
        AndroidStorageService.largeFileSupportFromMounts(mounts, sdPath),
        isNull,
      );
    });

    test('אחסון פנימי (emulated או מחוץ ל-/storage) — תומך תמיד', () {
      const mounts = '';
      expect(
        AndroidStorageService.largeFileSupportFromMounts(
          mounts,
          '/storage/emulated/0/Android/data/pkg/files',
        ),
        isTrue,
      );
      expect(
        AndroidStorageService.largeFileSupportFromMounts(
          mounts,
          '/data/user/0/pkg/files',
        ),
        isTrue,
      );
    });

    test('sdcardfs מעל vfat — נקבע לפי המאונט התחתון', () {
      const mounts =
          '/dev/block/vold/public:179,65 /mnt/media_rw/ABCD-1234 '
          'vfat rw,dirsync 0 0\n'
          '/mnt/media_rw/ABCD-1234 /storage/ABCD-1234 sdcardfs rw 0 0\n';
      expect(
        AndroidStorageService.largeFileSupportFromMounts(mounts, sdPath),
        isFalse,
      );
    });
  });
}

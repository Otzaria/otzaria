import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/installed_fonts.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/file/system_font_locator_io.dart';

/// SFNT with a cmap (format 4) over [ranges] and a `post` table whose
/// isFixedPitch is [monospace].
Uint8List _sfnt(List<(int, int)> ranges, {bool monospace = false}) {
  final segCount = ranges.length + 1;
  final subLen = 16 + segCount * 8;
  final sub = ByteData(subLen)
    ..setUint16(0, 4)
    ..setUint16(2, subLen)
    ..setUint16(6, segCount * 2);
  for (var i = 0; i < ranges.length; i++) {
    sub.setUint16(14 + i * 2, ranges[i].$2); // endCode
    sub.setUint16(16 + segCount * 2 + i * 2, ranges[i].$1); // startCode
  }
  sub.setUint16(14 + ranges.length * 2, 0xFFFF);
  sub.setUint16(16 + segCount * 2 + ranges.length * 2, 0xFFFF);
  sub.setUint16(16 + segCount * 4 + ranges.length * 2, 1); // idDelta

  final cmap = ByteData(12 + subLen)
    ..setUint16(2, 1)
    ..setUint16(4, 3)
    ..setUint16(6, 1)
    ..setUint32(8, 12);
  for (var i = 0; i < subLen; i++) {
    cmap.setUint8(12 + i, sub.getUint8(i));
  }

  final post = ByteData(32)..setUint32(12, monospace ? 1 : 0);

  const cmapOffset = 12 + 2 * 16;
  final postOffset = cmapOffset + cmap.lengthInBytes;
  final out = ByteData(postOffset + post.lengthInBytes)
    ..setUint32(0, 0x00010000)
    ..setUint16(4, 2);
  void record(int at, String tag, int offset, int length) {
    for (var j = 0; j < 4; j++) {
      out.setUint8(at + j, tag.codeUnitAt(j));
    }
    out.setUint32(at + 8, offset);
    out.setUint32(at + 12, length);
  }

  record(12, 'cmap', cmapOffset, cmap.lengthInBytes);
  record(28, 'post', postOffset, post.lengthInBytes);
  for (var i = 0; i < cmap.lengthInBytes; i++) {
    out.setUint8(cmapOffset + i, cmap.getUint8(i));
  }
  for (var i = 0; i < post.lengthInBytes; i++) {
    out.setUint8(postOffset + i, post.getUint8(i));
  }
  return out.buffer.asUint8List();
}

const _latin = (0x20, 0x7E);
const _hebrew = (0x5D0, 0x5EA);
const _cyrillic = (0x410, 0x44F);
const _cjk = (0x4E00, 0x9FFF);

SystemFontScanResult _scan() => AppFonts.debugBuildScan([
  MapEntry('/fonts/Plain.ttf', _sfnt([_latin])),
  MapEntry('/fonts/Hebrew Serif.ttf', _sfnt([_latin, _hebrew])),
  MapEntry('/fonts/Code.ttf', _sfnt([_latin], monospace: true)),
  MapEntry('/fonts/Wide.otf', _sfnt([_latin, _cyrillic, _cjk])),
]);

void main() {
  tearDown(() {
    AppFonts.debugResetSystemFontsCache();
    debugDefaultTargetPlatformOverride = null;
  });

  group('scan records scripts and fixed pitch per family', () {
    test('scripts come from what the cmap covers', () {
      final all = _scan().allFamilies;
      expect(all['Plain']!.scripts, ['latin']);
      expect(all['Hebrew Serif']!.scripts, ['hebrew', 'latin']);
      expect(all['Wide']!.scripts, ['cjk', 'cyrillic', 'latin']);
    });

    test('monospace comes from the post table', () {
      final all = _scan().allFamilies;
      expect(all['Code']!.monospace, isTrue);
      expect(all['Plain']!.monospace, isFalse);
    });
  });

  group('fonts.listInstalled from the app scan (macOS and Linux)', () {
    test('lists every scanned family, sorted, in the documented shape', () {
      final result = InstalledFonts.fromScan(
        _scan().allFamilies.values,
        platform: 'macos',
      );
      expect(result['platform'], 'macos');
      final families = (result['families'] as List).cast<Map>();
      expect(families.map((f) => f['name']), [
        'Code',
        'Hebrew Serif',
        'Plain',
        'Wide',
      ]);
      final hebrew = families.singleWhere((f) => f['name'] == 'Hebrew Serif');
      expect(hebrew, {
        'name': 'Hebrew Serif',
        'scripts': ['hebrew', 'latin'],
        'monospace': false,
      });
      expect(
        families.singleWhere((f) => f['name'] == 'Code')['monospace'],
        isTrue,
      );
    });

    test('installedFamilies is null until the scan cache is warm', () async {
      expect(AppFonts.installedFamilies(), isNull);
      await AppFonts.debugStoreScan(_scan());
      expect(
        AppFonts.installedFamilies()!.map((f) => f.family),
        containsAll(['Code', 'Plain']),
      );
    });
  });

  group('Android system fonts', () {
    test('the Android system font directories are scanned', () {
      final dirs = fontDirectoriesFor('android', const {});
      expect(dirs, contains('/system/fonts'));
    });

    test(
      'the scan runs on Android and on iOS (user-imported fonts + native names)',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(AppFonts.systemFontsReady, isFalse, reason: 'scan is pending');
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(
          AppFonts.systemFontsReady,
          isFalse,
          reason: 'native names and user fonts pending',
        );
      },
    );
  });
}

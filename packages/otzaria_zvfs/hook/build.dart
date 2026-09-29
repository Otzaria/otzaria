import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _zstdDirs = [
  'third_party/zstd/lib/common',
  'third_party/zstd/lib/compress',
  'third_party/zstd/lib/decompress',
  'third_party/zstd/lib/dictBuilder',
];

const _ownSources = [
  'src/zvfs_platform.c',
  'src/zvfs_core.c',
  'src/zvfs_convert.c',
  'src/zvfs_dicts.c',
  'src/zvfs_sqlite.c',
  'src/zvfs_overlay.c',
  'src/zvfs_reader.c',
  'src/zvfs_compact.c',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final root = input.packageRoot;
    final zstdSources = <String>[
      for (final dir in _zstdDirs)
        for (final entity in Directory.fromUri(
          root.resolve('$dir/'),
        ).listSync()..sort((a, b) => a.path.compareTo(b.path)))
          if (entity is File && entity.path.endsWith('.c'))
            '$dir/${entity.uri.pathSegments.last}',
    ];
    final os = input.config.code.targetOS;

    // Keep in sync with test/c/CMakeLists.txt.
    final builder = CBuilder.library(
      name: 'otzaria_zvfs',
      assetName: 'src/ffi/native.dart',
      sources: [...zstdSources, ..._ownSources],
      includes: const [
        'src',
        'third_party/zstd/lib',
        'third_party/sqlite',
      ],
      defines: const {
        'ZSTD_DISABLE_ASM': '1',
        'ZSTD_LEGACY_SUPPORT': '0',
        'ZSTD_TRACE': '0',
        // Empty visibility macros + -fvisibility=hidden keep zstd private.
        'ZSTDLIB_VISIBLE': '',
        'ZSTDERRORLIB_VISIBLE': '',
        'ZDICTLIB_VISIBLE': '',
        'ZSTDLIB_STATIC_API': '',
        'ZDICTLIB_STATIC_API': '',
      },
      flags: [
        if (os != OS.windows) '-fvisibility=hidden',
        if (os == OS.linux || os == OS.android) ...[
          '-ffunction-sections',
          '-fdata-sections',
          '-Wl,--gc-sections',
          '-Wl,-Bsymbolic',
        ],
        if (os == OS.macOS || os == OS.iOS) ...[
          '-headerpad_max_install_names',
          '-install_name',
          '@rpath/libotzaria_zvfs.dylib',
        ],
      ],
      libraries: [if (os == OS.linux) 'pthread'],
    );
    await builder.run(input: input, output: output);
  });
}

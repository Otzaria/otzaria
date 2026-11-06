import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_font_bootstrap.dart';
import 'package:otzaria/plugins/services/plugin_font_scheme.dart';
import 'package:otzaria/plugins/services/plugin_fonts.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/app_fonts.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const origin = 'otzaria-plugin://test.plugin';
  late Directory root;
  late PluginFontSchemeLease lease;

  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('plugin-font-scheme-');
    lease = PluginFontSchemeLease(origin: origin);
    debugResetPluginFonts();
  });
  tearDown(() async {
    lease.dispose();
    debugResetPluginFonts();
    await root.delete(recursive: true);
  });

  Future<CustomSchemeResponse?> serve(String url, {bool active = true}) =>
      servePluginAsset(
        url: WebUri(url),
        pluginId: 'test.plugin',
        rootPath: root.path,
        fontLease: active ? lease : null,
        contentSecurityPolicy: "default-src 'self'; font-src 'self' data:",
      );

  test('default is off and opt-in cannot enable iOS or other platforms', () {
    expect(pluginMacFontSchemeOptIn, isFalse);
    expect(pluginMacFontSchemeEnabled, isFalse);
    for (final platform in ['ios', 'android', 'windows', 'linux', 'web']) {
      expect(
        pluginFontSchemeExperimentAllowed(platform: platform, enabled: true),
        isFalse,
      );
    }
    expect(
      pluginFontSchemeExperimentAllowed(platform: 'macos', enabled: false),
      isFalse,
    );
    expect(
      pluginFontSchemeExperimentAllowed(platform: 'macos', enabled: true),
      isTrue,
    );
  });

  test(
    'controller replacement rejects late callbacks without closing the new lease',
    () {
      final owner = PluginFontSchemeOwner();
      final first = Object();
      final second = Object();
      owner.attach(first);
      final firstLease = owner.begin(controller: first, origin: origin)!;
      owner.attach(second);
      expect(firstLease.isActive, isFalse);
      final secondLease = owner.begin(controller: second, origin: origin)!;
      owner.attach(second);
      expect(owner.lease, same(secondLease));
      expect(owner.begin(controller: first, origin: origin), isNull);
      owner.release(controller: first);
      expect(secondLease.isActive, isTrue);
      owner.attach(null);
      expect(secondLease.isActive, isFalse);
      expect(owner.lease, isNull);
    },
  );

  test('document replacement fences a pending font read', () async {
    final owner = PluginFontSchemeOwner();
    final controller = Object();
    owner.attach(controller);
    final first = owner.begin(controller: controller, origin: origin)!;
    final bytes = Completer<Uint8List>();
    final url = first.register('face', () => bytes.future);
    final pending = first.responseFor(WebUri(url));
    final second = owner.begin(controller: controller, origin: origin)!;
    bytes.complete(Uint8List.fromList([1]));
    expect(await pending, isNull);
    expect(first.responseBytes, 0);
    expect(second.isActive, isTrue);
    owner.release(controller: controller);
    expect(second.isActive, isFalse);
  });

  test(
    'opaque registration is lazy, deduplicated, and counts served bytes',
    () async {
      var reads = 0;
      final bytes = Uint8List.fromList([0, 1, 255]);
      final url = lease.register('/private/home/font.ttf', () async {
        reads++;
        return bytes;
      });
      expect(reads, 0);
      expect(url, startsWith('$origin/__otzaria_fonts__/'));
      expect(url, isNot(contains('private')));
      expect(
        lease.register('/private/home/font.ttf', () async => Uint8List(0)),
        url,
      );
      final response = await serve(url);
      expect(response?.data, bytes);
      expect(response?.contentType, 'font/ttf');
      expect(response?.headers?['Cache-Control'], 'no-store');
      expect(response?.headers?['Content-Security-Policy'], isNotNull);
      expect(reads, 1);
      expect(lease.requestCount, 1);
      expect(lease.responseCount, 1);
      expect(lease.responseBytes, 3);
    },
  );

  test('same-plugin documents cannot use each other\'s leases', () async {
    final other = PluginFontSchemeLease(origin: origin);
    addTearDown(other.dispose);
    final oldUrl = lease.register('face', () async => Uint8List.fromList([1]));
    final newUrl = other.register('face', () async => Uint8List.fromList([2]));
    expect(await other.read(WebUri(oldUrl)), isNull);
    expect(await lease.read(WebUri(newUrl)), isNull);
    lease.dispose();
    expect(await lease.read(WebUri(oldUrl)), isNull);
    expect(await other.read(WebUri(newUrl)), [2]);
    expect(
      () => lease.register('late', () async => Uint8List(1)),
      throwsStateError,
    );
  });

  test(
    'release during I/O discards late bytes and does not count a response',
    () async {
      final pending = Completer<Uint8List>();
      final url = lease.register('face', () => pending.future);
      final response = serve(url);
      lease.dispose();
      pending.complete(Uint8List.fromList([3, 4]));
      expect(await response, isNull);
      expect(lease.requestCount, 1);
      expect(lease.responseBytes, 0);
    },
  );

  test(
    'reserved malformed or unknown routes never fall through to files',
    () async {
      const reserved = '__otzaria_fonts__';
      await Directory('${root.path}/$reserved/unknown').create(recursive: true);
      await File(
        '${root.path}/$reserved/unknown/font.ttf',
      ).writeAsString('private');
      await File('${root.path}/public.txt').writeAsString('ordinary');
      final font = lease.register('known', () async => Uint8List.fromList([8]));
      final invalid = [
        '$origin/$reserved/unknown/font.ttf',
        '$origin/$reserved/../public.txt',
        '$origin/$reserved/%2e%2e/public.txt',
        '$origin/%5f%5fotzaria_fonts%5f%5f/unknown/font.ttf',
        '$origin/%255f%255fotzaria_fonts%255f%255f/unknown/font.ttf',
        '$origin/folder/../$reserved/unknown/font.ttf',
        '$origin/$reserved/%ZZ/public.txt',
        '$origin/$reserved/..%2fpublic.txt',
        '$origin/$reserved/..%5cpublic.txt',
        font.replaceFirst('/__', '/%5f_'),
        '$font?version=1',
        '$font#fragment',
        font.replaceFirst('test.plugin/', 'test.plugin:1/'),
        font.replaceFirst('test.plugin/', 'user@test.plugin/'),
        font.replaceFirst('test.plugin', 'other.plugin'),
        font.replaceFirst('otzaria-plugin:', 'https:'),
      ];
      for (final url in invalid) {
        expect(await serve(url), isNull, reason: url);
      }
      expect(await serve(font, active: false), isNull);
      expect(lease.requestCount, 0);
      expect((await serve('$origin/public.txt'))?.data, 'ordinary'.codeUnits);
      await File('${root.path}/regular asset.css').writeAsString('body{}');
      await File(
        '${root.path}/ordinary__otzaria_fonts__note.txt',
      ).writeAsString('ok');
      expect(
        (await serve('$origin/ordinary__otzaria_fonts__note.txt'))?.data,
        'ok'.codeUnits,
      );
      expect(
        (await serve('$origin/regular%20asset.css'))?.data,
        'body{}'.codeUnits,
      );
    },
  );

  test(
    'CSS keeps bold, variable weights and lazy selected system files',
    () async {
      final regular = File('${root.path}/private-regular.ttf');
      final bold = File('${root.path}/private-bold.ttf');
      await regular.writeAsBytes([1]);
      await bold.writeAsBytes([2]);
      debugPluginSystemFaces = (family) => family == 'Probe System'
          ? SystemFontFamilyFaces(
              family: family,
              regularPath: regular.path,
              boldPath: bold.path,
              hasWeightAxis: false,
            )
          : null;
      final css = await buildPluginFontFaceCss(
        lease: lease,
        families: {'FrankRuhlCLM', 'Rubik', 'Probe System'},
      );
      expect(css.length, lessThan(2500));
      expect(
        css,
        contains(
          "font-family:'FrankRuhlCLM';font-style:normal;font-weight:700",
        ),
      );
      expect(
        css,
        contains("font-family:'Rubik';font-style:normal;font-weight:100 900"),
      );
      expect(css, isNot(contains('data:')));
      expect(css, isNot(contains(root.path)));
      expect(css, isNot(contains('private-regular')));
      final systemUrls = RegExp(
        r"font-family:'Probe System';[^}]*src:url\(([^)]+)\)",
      ).allMatches(css).map((m) => m[1]!).toList();
      await regular.writeAsBytes([5, 6]);
      expect(await lease.read(WebUri(systemUrls[0])), [5, 6]);
      expect(await lease.read(WebUri(systemUrls[1])), [2]);
      final resolved = await resolvePluginFontFamilies([
        {
          'name': 'Alias',
          'substitutes': ['Probe System'],
        },
      ]);
      expect(resolved['css'], contains('data:font/ttf;base64,'));
      expect(resolved['css'], isNot(contains('__otzaria_fonts__')));
    },
  );
}

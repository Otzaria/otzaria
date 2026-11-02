import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_fonts.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// ה-`@font-face` שאוצריא רושמת ב-WebView של תוסף. משפחה חסרה, face בולד
/// חסר או טווח משקלים חסר — כולם מתבטאים אצל המשתמש כגופן שגוי או מרוח.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    debugResetPluginFonts();
    debugPluginFontsFromFileServer = true;
  });

  tearDown(() => debugPluginFontsFromFileServer = null);

  tearDownAll(() => PluginFileServer.instance.close());

  List<String> rulesOf(String css, String family) => css
      .split('\n')
      .where((r) => r.contains("font-family:'$family'"))
      .toList();

  String sourceOf(String rule) =>
      RegExp(r'src:url\("?([^"\)]+)"?\)').firstMatch(rule)!.group(1)!;

  group('buildPluginFontFaceCss', () {
    test('כל הגופנים המובנים נשלחים, לא רק שני הנבחרים בהגדרות', () async {
      final css = await buildPluginFontFaceCss();
      for (final family in AppFonts.fontPaths.keys) {
        expect(
          css,
          contains("font-family:'$family'"),
          reason: 'התוסף יכול לנקוב ב-$family, ובלי face הוא ייפול ל-fallback',
        );
      }
    });

    test('גופן עם קובץ בולד נפרד מקבל גם face של 700', () async {
      final rules = rulesOf(await buildPluginFontFaceCss(), 'FrankRuhlCLM');
      expect(rules.length, 2);
      expect(rules.where((r) => r.contains('font-weight:400')), hasLength(1));
      expect(rules.where((r) => r.contains('font-weight:700')), hasLength(1));
    });

    test('גופן משתנה מקבל טווח משקלים ולא משקל בודד', () async {
      final css = await buildPluginFontFaceCss();
      for (final family in AppFonts.variableWeightFonts) {
        if (!AppFonts.fontPaths.containsKey(family)) continue;
        expect(rulesOf(css, family).single, contains('font-weight:100 900'));
      }
    });

    test('גופן שאינו משתנה ואין לו קובץ בולד מקבל face יחיד', () async {
      final rules = rulesOf(await buildPluginFontFaceCss(), 'Shofar');
      expect(rules, hasLength(1));
      expect(rules.single, contains('font-weight:400'));
    });

    test('הכללים מפנים לשרת הקבצים ואינם נושאים את הבייטים', () async {
      final css = await buildPluginFontFaceCss();
      final port = await PluginFileServer.instance.ensurePort();
      expect(css, isNot(contains('base64')));
      expect(css, isNot(contains('data:')));
      for (final rule in css.split('\n')) {
        expect(sourceOf(rule), startsWith('http://127.0.0.1:$port/fonts/'));
      }
      // ב-base64 זה היה כ-2MB.
      expect(css.length, lessThan(4000));
    });

    test('כל URL מגיש בדיוק את בייטי ה-asset שלו', () async {
      final css = await buildPluginFontFaceCss();
      for (final rule in rulesOf(css, 'FrankRuhlCLM')) {
        final asset = rule.contains('font-weight:700')
            ? AppFonts.boldFontPaths['FrankRuhlCLM']!
            : AppFonts.fontPaths['FrankRuhlCLM']!;
        final expected = (await rootBundle.load(asset)).buffer.asUint8List();
        final served = await PluginFileServer.instance.fontBytesFor(
          Uri.parse(sourceOf(rule)),
        );
        expect(served, expected);
      }
    });

    test('משפחה שאינה קיימת אינה מקבלת כלל', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyFontFamily,
        'No Such Font For Test',
      );
      addTearDown(
        () => Settings.setValue<String>(
          SettingsRepository.keyFontFamily,
          AppFonts.defaultFont,
        ),
      );
      expect(
        await buildPluginFontFaceCss(),
        isNot(contains('No Such Font For Test')),
      );
    });

    test('fallback מטביע את כל הבייטים גם כששרת הקבצים זמין', () async {
      final css = await buildPluginFontFaceCss(embedded: true);
      expect(css, isNot(contains('http:')));
      for (final rule in css.split('\n')) {
        expect(sourceOf(rule), startsWith('data:font/ttf;base64,'));
      }
      final regular = rulesOf(css, 'Shofar').single;
      final expected = (await rootBundle.load(
        AppFonts.fontPaths['Shofar']!,
      )).buffer.asUint8List();
      expect(
        sourceOf(regular),
        'data:font/ttf;base64,${base64Encode(expected)}',
      );
    });

    test('בלי שרת קבצים (iOS) הבייטים מוטבעים כ-data:', () async {
      debugPluginFontsFromFileServer = false;
      final rule = rulesOf(await buildPluginFontFaceCss(), 'Shofar').single;
      final expected = (await rootBundle.load(
        AppFonts.fontPaths['Shofar']!,
      )).buffer.asUint8List();
      expect(sourceOf(rule), 'data:font/ttf;base64,${base64Encode(expected)}');
    });
  });

  group('גופן מערכת שנבחר בהגדרות', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('plugin_fonts_system');
      await Settings.setValue<String>(
        SettingsRepository.keyFontFamily,
        'Test System Font',
      );
    });

    tearDown(() async {
      await Settings.setValue<String>(
        SettingsRepository.keyFontFamily,
        AppFonts.defaultFont,
      );
      await dir.delete(recursive: true);
    });

    SystemFontFamilyFaces faces({String? bold, bool axis = false}) =>
        SystemFontFamilyFaces(
          family: 'Test System Font',
          regularPath: '${dir.path}/regular.ttf',
          boldPath: bold,
          hasWeightAxis: axis,
        );

    test('נרשם עם bold, ומוגש מהדיסק בלי לחשוף את הנתיב', () async {
      File('${dir.path}/regular.ttf').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/bold.ttf').writeAsBytesSync([4, 5]);
      debugPluginSystemFaces = (family) => family == 'Test System Font'
          ? faces(bold: '${dir.path}/bold.ttf')
          : null;

      final rules = rulesOf(await buildPluginFontFaceCss(), 'Test System Font');
      expect(rules, hasLength(2));
      expect(rules.join(), isNot(contains('plugin_fonts_system')));
      final regular = rules.firstWhere((r) => r.contains('font-weight:400'));
      final bold = rules.firstWhere((r) => r.contains('font-weight:700'));
      final server = PluginFileServer.instance;
      expect(await server.fontBytesFor(Uri.parse(sourceOf(regular))), [
        1,
        2,
        3,
      ]);
      expect(await server.fontBytesFor(Uri.parse(sourceOf(bold))), [4, 5]);
    });

    test('גופן משתנה מקבל טווח משקלים, ובולד חסר בדיסק מושמט', () async {
      File('${dir.path}/regular.ttf').writeAsBytesSync([1]);
      debugPluginSystemFaces = (family) => family == 'Test System Font'
          ? faces(bold: '${dir.path}/missing.ttf', axis: true)
          : null;

      final rules = rulesOf(await buildPluginFontFaceCss(), 'Test System Font');
      expect(rules.single, contains('font-weight:100 900'));
    });

    test('RPC אינו שומר בייטים של גופני מערכת בין בקשות', () async {
      final file = File('${dir.path}/regular.ttf');
      await file.writeAsBytes([1, 2, 3]);
      debugPluginSystemFaces = (family) =>
          family == 'Test System Font' ? faces() : null;
      Future<String> resolve() async =>
          (await resolvePluginFontFamilies([
                {
                  'name': 'Alias',
                  'substitutes': ['Test System Font'],
                },
              ]))['css']
              as String;
      final first = await resolve();
      await file.writeAsBytes([4, 5, 6]);
      final second = await resolve();
      expect(first, contains(base64Encode([1, 2, 3])));
      expect(second, contains(base64Encode([4, 5, 6])));
    });

    test('קובץ רגיל שנמחק — אין כלל', () async {
      debugPluginSystemFaces = (family) =>
          family == 'Test System Font' ? faces() : null;
      expect(
        rulesOf(await buildPluginFontFaceCss(), 'Test System Font'),
        isEmpty,
      );
    });
  });

  group('pluginFontResponse (יירוט ב-Windows/Android)', () {
    Future<String> fontUrl() async =>
        sourceOf(rulesOf(await buildPluginFontFaceCss(), 'Shofar').single);

    test('משקף origin מותר ומצרף cache כמו השרת', () async {
      final url = await fontUrl();
      for (final origin in const [
        'null',
        'otzaria-plugin://a.b',
        'http://localhost:5173',
      ]) {
        final response = await pluginFontResponse(
          WebResourceRequest(url: WebUri(url), headers: {'Origin': origin}),
        );
        expect(response!.statusCode, 200);
        expect(response.headers!['Access-Control-Allow-Origin'], origin);
        expect(
          response.headers!['Cache-Control'],
          'max-age=31536000, immutable',
        );
        expect(response.contentType, 'font/ttf');
      }
    });

    test('origin אחר אינו מקבל CORS', () async {
      final response = await pluginFontResponse(
        WebResourceRequest(
          url: WebUri(await fontUrl()),
          headers: {'Origin': 'https://evil.example.com'},
        ),
      );
      expect(
        response!.headers,
        isNot(contains('Access-Control-Allow-Origin')),
      );
    });

    test('בלי Origin בבקשה (יירוט שאינו חושף אותו) — `*`', () async {
      final url = await fontUrl();
      for (final headers in [<String, String>{}, null]) {
        final response = await pluginFontResponse(
          WebResourceRequest(url: WebUri(url), headers: headers),
        );
        expect(response!.headers!['Access-Control-Allow-Origin'], '*');
        expect(response.headers, isNot(contains('Vary')));
      }
    });

    test('בקשה שאינה לגופן רשום אינה נענית', () async {
      final port = await PluginFileServer.instance.ensurePort();
      expect(
        await pluginFontResponse(
          WebResourceRequest(url: WebUri('http://127.0.0.1:$port/f/x/y')),
        ),
        isNull,
      );
    });

    test('הבייטים של גופן ארוז נטענים פעם אחת ונשמרים', () async {
      final url = Uri.parse(await fontUrl());
      final server = PluginFileServer.instance;
      final first = await server.fontBytesFor(url);
      expect(identical(await server.fontBytesFor(url), first), isTrue);
    });
  });

  group('installPluginFonts', () {
    test('מצליח רק כשהסקריפט החזיר true, עם הכללים והמטרות', () async {
      final controller = _FakeController(
        CallAsyncJavaScriptResult(value: true),
      );
      expect(
        await installPluginFonts(controller, css: 'X', targets: ['16px "A"']),
        isTrue,
      );
      expect(controller.arguments, {
        'css': 'X',
        'targets': ['16px "A"', '16px "FrankRuhlCLM"'],
        'timeoutMs': 1500,
      });
    });

    test('תשובה שאינה true או חריגה מחזירות false', () async {
      for (final controller in [
        _FakeController(CallAsyncJavaScriptResult(error: 'ReferenceError')),
        _FakeController(CallAsyncJavaScriptResult(value: false)),
        _FakeController(null),
        _FakeController(null, throws: true),
      ]) {
        expect(
          await installPluginFonts(controller, css: 'X', targets: const []),
          isFalse,
        );
      }
    });

    test('המתנה שנתקעה מעבר ל-timeout — false', () async {
      final controller = _FakeController(null, hangs: true);
      expect(
        await installPluginFonts(
          controller,
          css: 'X',
          targets: const [],
          timeout: const Duration(milliseconds: 10),
        ),
        isFalse,
      );
    });

    test('מטרת הבדיקה המובנית אינה מוכפלת כשכבר כלולה', () async {
      final controller = _FakeController(
        CallAsyncJavaScriptResult(value: true),
      );
      await installPluginFonts(
        controller,
        css: 'X',
        targets: ['16px "FrankRuhlCLM"'],
      );
      expect(controller.arguments!['targets'], ['16px "FrankRuhlCLM"']);
    });

    test('משפחות ללא כלל אינן עוקפות בדיקת transport של גופן מובנה', () async {
      final controller = _ScriptController('unmatched');
      await installPluginFonts(
        controller,
        css: 'X',
        targets: ['16px "Missing System Family"'],
      );
      expect(await controller.runScript(), isFalse);
    });

    test('targets ריקים אינם עוקפים בדיקת transport של גופן מובנה', () async {
      final controller = _ScriptController('unmatched');
      await installPluginFonts(controller, css: 'X', targets: const []);
      expect(await controller.runScript(), isFalse);
    });

    for (final outcome in ['loaded', 'blocked', 'pending']) {
      test('תוצאת טעינת הגופן ב-JS: $outcome', () async {
        final controller = _ScriptController(outcome);
        await installPluginFonts(
          controller,
          css: 'X',
          targets: ['16px "A"'],
          timeout: const Duration(milliseconds: 10),
        );
        expect(await controller.runScript(), outcome == 'loaded');
      });
    }

    test('בלי שרת קבצים (iOS) אינו נוגע בדף', () async {
      debugPluginFontsFromFileServer = false;
      final controller = _FakeController(
        CallAsyncJavaScriptResult(value: true),
      );
      expect(
        await installPluginFonts(controller, css: 'X', targets: const []),
        isFalse,
      );
      expect(controller.arguments, isNull);
    });
  });

  group('pluginFontFaceJson', () {
    test('זהה ל-jsonEncode ונשמר לאותו CSS', () {
      const css = "@font-face{font-family:'A';}";
      final first = pluginFontFaceJson(css);
      expect(first, jsonEncode(css));
      expect(identical(pluginFontFaceJson(css), first), isTrue);
      expect(pluginFontFaceJson('x'), jsonEncode('x'));
    });
  });

  group('fonts.resolveFamilies', () {
    test('מחזיר את הגופן של התחליף תחת השם שהמסמך ביקש', () async {
      final result = await resolvePluginFontFamilies([
        {
          'name': 'Missing Document Font',
          'substitutes': ['No Such Substitute', 'FrankRuhlCLM'],
        },
      ]);

      expect(result['resolved'], ['Missing Document Font']);
      final css = result['css'] as String;
      expect(css, contains("font-family:'Missing Document Font'"));
      expect(css, contains('data:font/ttf;base64,'));
    });

    test('הכינוי מחזיר בייטים עצמאיים של התחליף', () async {
      final own = [
        for (final asset in [
          AppFonts.fontPaths['FrankRuhlCLM']!,
          AppFonts.boldFontPaths['FrankRuhlCLM']!,
        ])
          'data:font/ttf;base64,${base64Encode((await rootBundle.load(asset)).buffer.asUint8List())}',
      ];
      final result = await resolvePluginFontFamilies([
        {
          'name': 'Alias',
          'substitutes': ['FrankRuhlCLM'],
        },
      ]);
      final alias = rulesOf(result['css'] as String, 'Alias');
      expect(alias.map(sourceOf), own);
    });

    test('מגביל את מספר המשפחות בבקשה אחת', () async {
      final result = await resolvePluginFontFamilies([
        for (var i = 0; i < 25; i++)
          {
            'name': 'Missing $i',
            'substitutes': ['FrankRuhlCLM'],
          },
      ]);

      expect(result['resolved'], hasLength(24));
    });
  });

  group('pluginFontLoadTargets', () {
    test('רגיל ובולד לקריאה ולמפרשים, רגיל לממשק, בלי כפילויות', () {
      final targets = pluginFontLoadTargets({
        'typography': {
          'fontFamily': 'FrankRuhlCLM',
          'commentatorsFontFamily': 'FrankRuhlCLM',
          'uiFontFamily': 'Rubik',
        },
      });
      expect(targets, [
        '16px "FrankRuhlCLM"',
        'bold 16px "FrankRuhlCLM"',
        '16px "Rubik"',
      ]);
    });

    test('שם עם מירכאות אינו שובר את ה-shorthand', () {
      final targets = pluginFontLoadTargets({
        'typography': {'uiFontFamily': 'A"B'},
      });
      expect(targets, [r'16px "A\"B"']);
    });

    test('בלי typography אין מה לטעון', () {
      expect(pluginFontLoadTargets(const {}), isEmpty);
    });
  });

  group('typography ב-theme payload', () {
    test('ברירת המחדל היא משפחה שנשלחת בפועל כ-@font-face', () async {
      final css = await buildPluginFontFaceCss();
      final typography = _typography();
      expect(css, contains("font-family:'${typography['fontFamily']}'"));
      expect(
        css,
        contains("font-family:'${typography['commentatorsFontFamily']}'"),
      );
    });

    test('גופן הממשק נפרד מגופן הקריאה ונשלח כ-@font-face', () async {
      // בלי שדה נפרד, כותב תוסף מחיל את גופן הקריאה על כפתורים בני 12px,
      // וגופן ספרים בגודל כזה נמרח.
      final typography = _typography();
      expect(typography['uiFontFamily'], isNot(typography['fontFamily']));
      expect(
        await buildPluginFontFaceCss(),
        contains("font-family:'${typography['uiFontFamily']}'"),
      );
    });

    test('גופן שנבחר בהגדרות הוא זה שמגיע ב-payload', () async {
      await Settings.setValue<String>(
        SettingsRepository.keyFontFamily,
        'TaameyDavidCLM',
      );
      addTearDown(
        () => Settings.setValue<String>(
          SettingsRepository.keyFontFamily,
          AppFonts.defaultFont,
        ),
      );
      final typography = _typography();
      expect(typography['fontFamily'], 'TaameyDavidCLM');
    });

    test('המטרות להמתנה הן משפחות ה-typography', () {
      final typography = _typography();
      final targets = pluginFontLoadTargets({'typography': typography});
      expect(targets, contains('16px "${typography['fontFamily']}"'));
      expect(targets, contains('bold 16px "${typography['fontFamily']}"'));
      expect(targets, contains('16px "${typography['uiFontFamily']}"'));
    });
  });
}

Map<String, dynamic> _typography() =>
    buildThemePayloadFromScheme(
          AppThemeData.createColorScheme(Colors.blue, Brightness.light),
          isDark: false,
          density: AppDensity.regular,
        )['typography']
        as Map<String, dynamic>;

class _FakeController extends Fake implements InAppWebViewController {
  _FakeController(this.result, {this.throws = false, this.hangs = false});

  final CallAsyncJavaScriptResult? result;
  final bool throws;
  final bool hangs;
  late String functionBody;
  Map<String, dynamic>? arguments;

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const <String, dynamic>{},
    ContentWorld? contentWorld,
  }) async {
    this.functionBody = functionBody;
    this.arguments = arguments;
    if (throws) throw PlatformException(code: 'unsupported');
    if (hangs) await Completer<void>().future;
    return result;
  }
}

class _ScriptController extends _FakeController {
  _ScriptController(this.outcome)
    : super(CallAsyncJavaScriptResult(value: true));

  final String outcome;

  // זמן התנעת Node אינו חלק מזמן ההמתנה לגופן ב-WebView שכבר פועל.
  Future<bool> runScript() async {
    final result = await Process.run('node', [
      '-e',
      """
const document = {
  createElement: () => ({setAttribute() {}, remove() {}}),
  head: {appendChild() {}},
  fonts: {load(target) {
    if (${jsonEncode(outcome)} === 'unmatched') {
      return target === '16px "FrankRuhlCLM"'
        ? Promise.reject(new Error('CSP')) : Promise.resolve([]);
    }
    if (${jsonEncode(outcome)} === 'blocked') return Promise.reject(new Error('CSP'));
    if (${jsonEncode(outcome)} === 'pending') return new Promise(() => {});
    return Promise.resolve([{}]);
  }}
};
(async function(css, targets, timeoutMs) {
$functionBody
})(...Object.values(${jsonEncode(arguments)}))
  .then(value => console.log(JSON.stringify({value})))
  .catch(error => console.log(JSON.stringify({error: String(error)})));
""",
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final response = jsonDecode(result.stdout.toString()) as Map;
    expect(response['error'], isNull);
    return response['value'] as bool;
  }
}

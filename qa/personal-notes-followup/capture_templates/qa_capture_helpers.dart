import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/app_theme_data.dart';

final boundaryKey = GlobalKey();
final String outputDirectory = Platform.environment['QA_CAPTURE_OUTPUT']!;
const localizations = <LocalizationsDelegate<dynamic>>[
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  mui.DefaultMaterialLocalizations.delegate,
];

ThemeData captureTheme() {
  final state = SettingsState.initial();
  final base = AppThemeData.light(
    AppThemeData.createColorScheme(state.seedColor, Brightness.light),
    compactMenuMode: state.compactMenuMode,
  );
  // The headless test font configuration needs an explicit real Hebrew fallback.
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['Rubik']),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamilyFallback: const ['Rubik']),
  );
}

Widget captureBuilder(BuildContext context, Widget? child) => RepaintBoundary(
  key: boundaryKey,
  child: Directionality(textDirection: TextDirection.rtl, child: child!),
);

Future<void> loadCaptureFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final value in manifest) {
    final entry = value as Map<String, dynamic>;
    final loader = FontLoader(entry['family'] as String);
    for (final font in entry['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load((font as Map<String, dynamic>)['asset'] as String));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['QA_FLUTTER_ROOT']!;
  final roboto = FontLoader('Roboto');
  for (final name in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf']) {
    final bytes = await File('$flutterRoot/bin/cache/artifacts/material_fonts/$name').readAsBytes();
    roboto.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await roboto.load();
}

Future<void> capture(WidgetTester tester, String name, {Finder? region}) async {
  await tester.pump();
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  Rect bounds = Offset.zero & boundary.size;
  if (region != null) {
    final origin = boundary.localToGlobal(Offset.zero);
    bounds = tester.getRect(region).shift(-origin).inflate(10).intersect(bounds);
  }
  await tester.runAsync(() async {
    final layer = boundary.layer! as OffsetLayer;
    final image = await layer.toImage(bounds, pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(outputDirectory)..createSync(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(data!.buffer.asUint8List());
    final record = {'name':name, 'file':file.path, 'width':image.width, 'height':image.height, 'capturedUtc':DateTime.now().toUtc().toIso8601String()};
    image.dispose();
    File('${directory.path}/captures.jsonl').writeAsStringSync('${jsonEncode(record)}\n', mode:FileMode.append);
    print('CAPTURE ${jsonEncode(record)}');
  });
}

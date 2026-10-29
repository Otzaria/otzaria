import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('סגירה ממתינה במסך מלא מתבטלת בהצגה, שחזור ו-Dock', () async {
    final executable = Platform.resolvedExecutable;
    final cache = executable.indexOf('${p.separator}bin${p.separator}cache');
    expect(cache, greaterThanOrEqualTo(0));
    final framework = p.join(
      executable.substring(0, cache),
      'bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64',
    );
    final managerSource = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final manager = managerSource.substring(
      managerSource.indexOf('final class OtzariaWindowManager {'),
    );
    final delegateSource = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final reopen = delegateSource.substring(
      delegateSource.indexOf('  override func applicationShouldHandleReopen('),
      delegateSource.indexOf(
        '  override func applicationSupportsSecureRestorableState(',
      ),
    );
    final fixture = File(
      'test/macos/fullscreen_close_probe.swift',
    ).readAsStringSync();
    final temporary = Directory.systemTemp.createTempSync(
      'otzaria-fullscreen-',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    final source = File(p.join(temporary.path, 'main.swift'));
    source.writeAsStringSync(
      fixture.replaceFirst(
        '/* RUNNER_SOURCE */',
        '$manager\nclass ProbeAppDelegate: FlutterAppDelegate {\n$reopen\n}',
      ),
    );
    final binary = p.join(temporary.path, 'fullscreen_probe');
    final compile = await Process.run('xcrun', [
      'swiftc',
      '-F',
      framework,
      '-framework',
      'FlutterMacOS',
      '-Xlinker',
      '-rpath',
      '-Xlinker',
      framework,
      source.path,
      '-o',
      binary,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final result = await Process.run(binary, []);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, skip: !Platform.isMacOS);
}

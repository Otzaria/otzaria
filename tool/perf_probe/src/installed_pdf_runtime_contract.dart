import 'package:path/path.dart' as p;

import 'installed_pdf_android_contract.dart';
import 'installed_pdf_desktop_contract.dart';
import 'installed_pdf_ios_contract.dart';
import 'installed_pdf_macos_contract.dart';

const installedPluginPdfRuntimePlatforms = {
  'linux',
  'windows',
  'android',
  'macos',
};
const installedPdfRuntimePlatforms = {
  ...installedPluginPdfRuntimePlatforms,
  'ios',
};

const installedPdfRuntimeSteps = [
  'view',
  'concurrentWork',
  'cancelAndRecover',
  'reopen',
  'loadedModules',
  'teardown',
];
const installedPdfRuntimeModules = {
  'linux': ['libpdfium.so', 'libpdfium_printing.so', 'libprinting_plugin.so'],
  'windows': ['pdfium.dll', 'pdfium_printing.dll', 'printing_plugin.dll'],
};

/// הנתיבים הממופים בתהליך, כולל רווחים בשמות תיקיות.
Set<String> installedPdfMappedPaths(String maps) {
  final pattern = RegExp(r'^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(/.+)$');
  return {
    for (final line in maps.split('\n'))
      if (pattern.firstMatch(line) case final match?) match.group(1)!,
  };
}

List<String> installedPdfModuleErrors({
  required String platform,
  required String bundleDirectory,
  required Set<String> mappedPaths,
  required Map<String, String> expectedPaths,
}) {
  final names = installedPdfRuntimeModules[platform];
  if (names == null) return ['Unsupported PDF runtime platform: $platform'];
  final windows = platform == 'windows';
  final paths = windows ? p.windows : p.posix;
  String normalized(String path) {
    if (!windows) return path;
    path = path.replaceAll('/', r'\');
    if (path.startsWith(r'\\?\UNC\')) {
      path = r'\\' + path.substring(8);
    } else if (path.startsWith(r'\\?\')) {
      path = path.substring(4);
    }
    return paths.normalize(path).toLowerCase();
  }

  final errors = <String>[];
  for (final name in names) {
    final observed = mappedPaths.where(
      (path) =>
          paths.basename(normalized(path)).replaceFirst(' (deleted)', '') ==
          name,
    );
    final expected = expectedPaths[name];
    final bundled = windows
        ? paths.join(bundleDirectory, name)
        : paths.join(bundleDirectory, 'lib', name);
    if (expected == null ||
        !paths.isAbsolute(bundled) ||
        normalized(expected) != normalized(bundled) ||
        observed.length != 1 ||
        normalized(observed.single) != normalized(expected)) {
      errors.add(
        '$name must be loaded only from $bundled (resolved: $expected): '
        '${observed.toList()}',
      );
    }
  }
  return errors;
}

List<String> installedPdfRuntimeErrors(
  Object? value, {
  required String platform,
}) {
  if (value is! Map) return ['Missing actual-bundle PDF runtime report'];
  final errors = <String>[];
  if (!installedPdfRuntimePlatforms.contains(platform) ||
      value['status'] != 'passed' ||
      value['platform'] != platform) {
    errors.add('Actual-bundle $platform PDF runtime did not pass');
  }
  final steps = value['steps'];
  if (installedPdfDesktopPlatforms.contains(platform)) {
    errors.addAll(
      installedPdfDesktopErrors(
        steps is Map ? steps['desktopLifecycle'] : null,
      ),
    );
    errors.addAll(
      installedPdfRepeatedLifecycleErrors(
        steps is Map ? steps['repeatedLifecycle'] : null,
      ),
    );
  }
  if (platform == 'android') {
    errors.addAll(
      installedAndroidPdfModuleErrors(
        steps is Map ? steps['loadedModules'] : null,
      ),
    );
  }
  if (platform == 'ios') {
    errors.addAll(
      installedPdfIosModuleErrors(
        steps is Map ? steps['loadedModules'] : null,
      ),
    );
  }
  for (final name in installedPdfRuntimeSteps) {
    if (steps is! Map ||
        steps[name] is! Map ||
        steps[name]['status'] != 'passed') {
      errors.add('Required PDF runtime step did not pass: $name');
    }
  }
  if (platform == 'macos') {
    errors.addAll(
      installedPdfMacosModuleErrors(
        steps is Map ? steps['loadedModules'] : null,
      ),
    );
  }
  if (value['bundlePathsVerified'] != true ||
      value['ownedDocumentsRemaining'] != 0 ||
      value['ownedTabsRemaining'] != 0 ||
      value['indexingActiveAfter'] != false) {
    errors.add('PDF runtime lacks bundle-path or teardown evidence');
  }
  return errors;
}

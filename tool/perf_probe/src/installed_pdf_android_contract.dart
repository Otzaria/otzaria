import 'package:path/path.dart' as p;

const installedPdfAndroidPackage = 'org.otzaria.otzaria.installedprobe';
const installedPdfAndroidBackend = 'android.graphics.pdf.PdfRenderer';

final _installedModule = RegExp(
  '^/data/app/(?:[A-Za-z0-9_~+=-]+/)?'
  '${RegExp.escape(installedPdfAndroidPackage)}-[A-Za-z0-9_~+=-]+'
  r'/lib/x86_64/libpdfium\.so$',
);

bool isInstalledAndroidPdfModule(String path) =>
    _installedModule.hasMatch(path);

bool isAndroidSystemPdfModule(String path) =>
    !path.endsWith(' (deleted)') &&
    p.posix.basename(path) == 'libpdfium.so' &&
    p.posix.normalize(path) == path &&
    const ['/system', '/system_ext', '/apex', '/product', '/vendor'].any(
      (root) => p.posix.isWithin(root, path),
    );

/// שומר גם מיפויים שנמחקו כדי שלא ייחשבו הוכחה לקובץ הנוכחי.
Set<String> installedAndroidPdfMappedPaths(
  String maps, {
  bool executableOnly = false,
}) {
  final pattern = RegExp(r'^\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(/.+)$');
  return {
    for (final line in maps.split('\n'))
      if (pattern.firstMatch(line) case final match?)
        if ((!executableOnly || match.group(1)!.contains('x')) &&
            p.posix.basename(match.group(2)!).replaceFirst(' (deleted)', '') ==
                'libpdfium.so')
          match.group(2)!,
  };
}

List<String> installedAndroidPdfModuleErrors(Object? value) {
  if (value is! Map) return ['Missing Android PDF module evidence'];
  final errors = <String>[];
  final module = value['appModule'];
  final observed = value['observedModulePaths'];
  final executable = value['executableModulePaths'];
  final system = value['systemModulePaths'];
  if (value['source'] != '/proc/self/maps' ||
      value['package'] != installedPdfAndroidPackage ||
      value['abi'] != 'x86_64' ||
      value['printingBackend'] != installedPdfAndroidBackend ||
      value['processId'] is! int ||
      (value['processId'] as int) <= 0 ||
      !value.containsKey('configuredPdfrxModule') ||
      value['configuredPdfrxModule'] != null) {
    errors.add('Android PDF module identity or backend is invalid');
  }
  if (module is! Map ||
      module['name'] != 'libpdfium.so' ||
      module['path'] is! String ||
      !isInstalledAndroidPdfModule(module['path'] as String) ||
      module['bytes'] is! int ||
      (module['bytes'] as int) < 64 ||
      module['sha256'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(module['sha256'] as String)) {
    errors.add('Android PDF runtime lacks its extracted module path and hash');
    return errors;
  }
  final path = module['path'] as String;
  if (observed is! List ||
      observed.any((item) => item is! String) ||
      observed.toSet().length != observed.length ||
      observed.where((item) => item == path).length != 1 ||
      observed.any(
        (item) => item != path && !isAndroidSystemPdfModule(item as String),
      ) ||
      executable is! List ||
      executable.any((item) => item is! String) ||
      executable.toSet().length != executable.length ||
      !executable.contains(path) ||
      executable.any((item) => !observed.contains(item)) ||
      system is! List ||
      system.any((item) => item is! String) ||
      system.toSet().length != system.length ||
      system.length != observed.length - 1 ||
      system.any((item) => item == path || !observed.contains(item))) {
    errors.add('Android PDF runtime has missing or foreign executable maps');
  }
  return errors;
}

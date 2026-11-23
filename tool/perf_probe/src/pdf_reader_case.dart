import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum PerfPdfSourceKind { generated, external }

class PerfPdfCase {
  const PerfPdfCase._({
    required this.sourceKind,
    required this.pageCount,
    required this.mixedPageSizes,
    required this.sourcePath,
    required this.externalSha256,
    required this.navigationTargets,
  });

  static const defaults = PerfPdfCase._(
    sourceKind: PerfPdfSourceKind.generated,
    pageCount: 600,
    mixedPageSizes: true,
    sourcePath: null,
    externalSha256: null,
    navigationTargets: PerfPdfNavigationTargets._(
      initialPage: 1,
      forwardPage: 450,
      backwardPage: 60,
      zoomFactor: 2,
    ),
  );

  factory PerfPdfCase.fromJson(Object? value, {required String baseDirectory}) {
    final json = _object(value, 'PDF case', {
      'schemaVersion',
      'source',
      'navigation',
    });
    if (json['schemaVersion'] is! int || json['schemaVersion'] != 1) {
      throw const FormatException('PDF case schemaVersion must be integer 1.');
    }
    final source = _object(json['source'], 'source', {
      'kind',
      'pageCount',
      'mixedPageSizes',
      'path',
      'sha256',
    });
    final kind = switch (source['kind']) {
      'generated' => PerfPdfSourceKind.generated,
      'external' => PerfPdfSourceKind.external,
      _ => throw const FormatException(
        'source.kind must be generated or external.',
      ),
    };
    final pages = _integer(source['pageCount'], 'source.pageCount', 1, 10000);
    bool? mixed;
    String? sourcePath;
    String? expectedHash;
    if (kind == PerfPdfSourceKind.generated) {
      if (source.containsKey('path') || source.containsKey('sha256')) {
        throw const FormatException('Generated PDFs cannot specify a file.');
      }
      final value = source.containsKey('mixedPageSizes')
          ? source['mixedPageSizes']
          : true;
      if (value is! bool) {
        throw const FormatException('source.mixedPageSizes must be boolean.');
      }
      mixed = value;
    } else {
      if (source.containsKey('mixedPageSizes')) {
        throw const FormatException(
          'External PDF page sizes are observed, not declared as generated.',
        );
      }
      final path = source['path'];
      final hash = source['sha256'];
      if (path is! String || path.trim().isEmpty || path.contains('\u0000')) {
        throw const FormatException('source.path must be a nonempty path.');
      }
      if (hash is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
        throw const FormatException(
          'source.sha256 must be a SHA-256 hex digest.',
        );
      }
      sourcePath = p.normalize(p.join(p.absolute(baseDirectory), path));
      expectedHash = hash.toLowerCase();
    }
    final navigation = json.containsKey('navigation')
        ? _object(json['navigation'], 'navigation', {
            'initialPage',
            'forwardPage',
            'backwardPage',
            'zoomFactor',
          })
        : <String, Object?>{};
    int target(String key, int fallback) => navigation.containsKey(key)
        ? _integer(navigation[key], 'navigation.$key', 1, pages)
        : fallback.clamp(1, pages).toInt();
    final initialPage = target('initialPage', 1);
    final forwardPage = target(
      'forwardPage',
      (pages * 3 ~/ 4).clamp(initialPage, pages).toInt(),
    );
    final backwardPage = target(
      'backwardPage',
      (pages ~/ 10).clamp(1, forwardPage).toInt(),
    );
    if (forwardPage < initialPage || backwardPage > forwardPage) {
      throw const FormatException(
        'Navigation must jump forward from initialPage, then backward.',
      );
    }
    final zoom = navigation.containsKey('zoomFactor')
        ? navigation['zoomFactor']
        : 2;
    if (zoom is! num || !zoom.isFinite || zoom <= 1 || zoom > 16) {
      throw const FormatException('navigation.zoomFactor must be in (1, 16].');
    }
    return PerfPdfCase._(
      sourceKind: kind,
      pageCount: pages,
      mixedPageSizes: mixed,
      sourcePath: sourcePath,
      externalSha256: expectedHash,
      navigationTargets: PerfPdfNavigationTargets._(
        initialPage: initialPage,
        forwardPage: forwardPage,
        backwardPage: backwardPage,
        zoomFactor: zoom.toDouble(),
      ),
    );
  }

  final PerfPdfSourceKind sourceKind;
  final int pageCount;
  final bool? mixedPageSizes;
  final String? sourcePath;
  final String? externalSha256;
  final PerfPdfNavigationTargets navigationTargets;

  static Future<PerfPdfCase> load(String path) async {
    if (path.isEmpty) return defaults;
    final file = File(path).absolute;
    if (await file.length() > 64 * 1024) {
      throw const FormatException('PDF case JSON must fit in 64 KiB.');
    }
    final text = await file.readAsString();
    return PerfPdfCase.fromJson(
      jsonDecode(text.startsWith('\ufeff') ? text.substring(1) : text),
      baseDirectory: file.parent.path,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'source': {
      'kind': sourceKind.name,
      'pageCount': pageCount,
      if (mixedPageSizes != null) 'mixedPageSizes': mixedPageSizes,
      if (sourcePath != null) 'path': sourcePath,
      if (externalSha256 != null) 'sha256': externalSha256,
    },
    'navigation': navigationTargets.toJson(),
  };

  Map<String, Object?> toComparisonJson() => {
    'schemaVersion': 1,
    'source': {
      'kind': sourceKind.name,
      'pageCount': pageCount,
      if (mixedPageSizes != null) 'mixedPageSizes': mixedPageSizes,
      if (externalSha256 != null) 'sha256': externalSha256,
    },
    'navigation': {
      ...navigationTargets.toJson(),
      'zoomPage': navigationTargets.zoomPage,
      'zoomAnchor': 'pageCenter',
    },
  };

  Future<void> verifyExternalSource() async {
    if (sourceKind != PerfPdfSourceKind.external) return;
    if (await FileSystemEntity.type(sourcePath!) != FileSystemEntityType.file) {
      throw StateError('External PDF must be a regular file.');
    }
    final digest = (await sha256.bind(File(sourcePath!).openRead()).first)
        .toString();
    if (digest != externalSha256) {
      throw StateError('External PDF does not match source.sha256.');
    }
  }

  void verifyPageCount(int actual) {
    if (actual != pageCount) {
      throw StateError(
        'PDF case expects $pageCount pages; reader found $actual.',
      );
    }
  }
}

class PerfPdfNavigationTargets {
  const PerfPdfNavigationTargets._({
    required this.initialPage,
    required this.forwardPage,
    required this.backwardPage,
    required this.zoomFactor,
  });

  final int initialPage;
  final int forwardPage;
  final int backwardPage;
  final double zoomFactor;
  int get zoomPage => backwardPage;

  Map<String, Object> toJson() => {
    'initialPage': initialPage,
    'forwardPage': forwardPage,
    'backwardPage': backwardPage,
    'zoomFactor': zoomFactor,
  };
}

Map<String, Object?> _object(Object? value, String name, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.keys.any((key) => !keys.contains(key))) {
    throw FormatException('$name must be an object with known fields.');
  }
  return value;
}

int _integer(Object? value, String name, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw FormatException('$name must be an integer in $minimum..$maximum.');
  }
  return value;
}

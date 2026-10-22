import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/marker/legacy/legacy_marker_import.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_book_index.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:path/path.dart' as p;

/// קובץ שאינו גיבוי של המרקר, או שאי אפשר לקרוא.
class MarkerBackupFormatException implements Exception {
  const MarkerBackupFormatException();
}

class MarkerBackupTooLargeException implements Exception {
  const MarkerBackupTooLargeException();
}

/// מה ייבוא ישנה, לפני שהוא נכתב.
class MarkerImportPreview {
  final List<MarkerHighlight> highlights;
  final MarkerPalette? palette;

  /// רשומות שנדחו בקריאה.
  final int invalid;

  final List<MarkerLegacyRef> importedLegacy;

  /// מזהים שכבר קיימים — ידולגו.
  final int existing;

  /// סימונים שיובאו מהתוסף בעבר ונמחקו מאז — אינם מוחזרים.
  final int deletedSinceImport;

  /// סימונים שהספר שלהם לא נמצא בספרייה. הם יובאו, ויוצגו כשהספר יתווסף.
  final int unknownBooks;

  /// ספרים שזוהו לפי המזהה היציב תחת כותרת חדשה.
  final int renamedBooks;

  const MarkerImportPreview({
    required this.highlights,
    this.palette,
    this.invalid = 0,
    this.existing = 0,
    this.deletedSinceImport = 0,
    this.unknownBooks = 0,
    this.renamedBooks = 0,
    this.importedLegacy = const [],
  });

  int get toAdd => highlights.length - existing;
}

/// גיבוי, שחזור וייבוא. הייבוא מוסיף בלבד ובטרנזקציה אחת: סימון קיים אינו
/// משתנה, וכשל באמצע אינו משאיר ייבוא חלקי.
class MarkerTransfer {
  MarkerTransfer({MarkerRepository? repository})
    : _repository = repository ?? MarkerRepository();

  static const String format = 'otzaria-marker';
  static const int schemaVersion = 1;
  static const int maxFileBytes = 64 * 1024 * 1024;
  static const int maxRecords = 100000;

  final MarkerRepository _repository;

  Map<String, Object?> _envelope(MarkerPalette palette) => {
    'format': format,
    'schemaVersion': schemaVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'palette': jsonDecode(palette.encode()),
  };

  /// סעיף המרקר בגיבוי של התוכנה, מקודד כבר.
  Future<String> backupSectionJson(MarkerPalette palette) =>
      _repository.backupJson(_envelope(palette));

  /// קובץ גיבוי של כל הסימונים, או רק של [only].
  Future<Uint8List> encodeBackup({
    required MarkerPalette palette,
    List<MarkerHighlight>? only,
  }) async => utf8.encode(
    only == null
        ? await _repository.backupJson(_envelope(palette), indent: true)
        : const JsonEncoder.withIndent('  ').convert({
            ..._envelope(palette),
            'highlights': [for (final h in only) h.toJson()],
          }),
  );

  /// קורא קובץ גיבוי — של המרקר או של התוסף הישן — ב-isolate נפרד, כדי
  /// שקובץ גדול לא יקפיא את כל החלונות.
  Future<MarkerImportPreview> previewFile(
    String path, {
    MarkerBookIndex? books,
  }) async {
    final file = File(path);
    if (await file.length() > maxFileBytes) {
      throw const MarkerBackupTooLargeException();
    }
    final parsed = await Isolate.run(() => _parseFile(path));
    // גם מקובץ הגיבוי של התוסף: מה שנמחק אחרי ייבוא קודם לא חוזר.
    return _preview(parsed, books, skipDeletedLegacy: parsed.fromPlugin);
  }

  /// הנתונים שהתוסף הישן שמר, או null כשאין לו סימונים.
  Future<MarkerImportPreview?> previewLegacyPlugin({
    MarkerBookIndex? books,
    PluginRegistryRepository? registry,
  }) async {
    final data = await readLegacyMarkerStore(
      registry ?? PluginRegistryRepository(),
    );
    if (data == null) return null;
    return _preview(data, books, skipDeletedLegacy: true);
  }

  Future<MarkerImportPreview> _preview(
    LegacyMarkerData data,
    MarkerBookIndex? books, {
    bool skipDeletedLegacy = false,
  }) async {
    var unknown = 0;
    var renamed = 0;
    final highlights = <MarkerHighlight>[];
    for (final highlight in data.highlights) {
      final book = books?.find(
        highlight.bookTitle,
        highlight.bookUid,
        pdf: highlight.pdf,
      );
      if (books != null && book == null) unknown++;
      if (book != null && book.title != highlight.bookTitle) {
        renamed++;
        highlights.add(highlight.copyWith(bookTitle: book.title));
      } else {
        highlights.add(highlight);
      }
    }
    final existing = await _repository.existingIds(
      highlights.map((highlight) => highlight.id),
    );
    var deleted = 0;
    if (skipDeletedLegacy) {
      final imported = await _repository.allImportedLegacyIds();
      highlights.removeWhere((highlight) {
        final gone =
            !existing.contains(highlight.id) &&
            highlight.segments.every(
              (segment) => imported.contains(segment.legacyId),
            );
        if (gone) deleted++;
        return gone;
      });
    }
    return MarkerImportPreview(
      highlights: highlights,
      palette: data.palette,
      invalid: data.invalid,
      existing: existing.length,
      deletedSinceImport: deleted,
      unknownBooks: unknown,
      renamedBooks: renamed,
      importedLegacy: data.importedLegacy,
    );
  }

  Future<MarkerImportSummary> apply(MarkerImportPreview preview) =>
      _repository.importHighlights(
        preview.highlights,
        importedLegacy: preview.importedLegacy,
      );

  /// שומר את כל הסימונים הנוכחיים לצד הגיבויים של התוכנה, ומחזיר את הנתיב.
  /// null כשאין מה לגבות.
  Future<String?> writeSafetyBackup(MarkerPalette palette) async {
    if (await _repository.countAll() == 0) return null;
    final bytes = await encodeBackup(palette: palette);
    final directory = Directory(
      p.join(await AppPaths.getBackupPath(), 'marker'),
    );
    await directory.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final file = File(
      p.join(directory.path, 'marker-before-import-$stamp.json'),
    );
    await file.writeAsBytes(bytes, flush: true);
    await _pruneSafetyBackups(directory);
    return file.path;
  }

  /// הגיבויים שלפני ייבוא נשמרים רק לאחרונים; השם ממוין לפי הזמן.
  static const int _keptSafetyBackups = 10;

  static Future<void> _pruneSafetyBackups(Directory directory) async {
    try {
      final backups = [
        await for (final entity in directory.list())
          if (entity is File &&
              p.basename(entity.path).startsWith('marker-before-import-'))
            entity,
      ]..sort((a, b) => b.path.compareTo(a.path));
      for (final old in backups.skip(_keptSafetyBackups)) {
        await old.delete();
      }
    } catch (error) {
      // גיבוי ישן שלא נמחק אינו מפריע לייבוא.
      debugPrint('Marker: pruning old safety backups failed: $error');
    }
  }
}

LegacyMarkerData _parseFile(String path) {
  final Object? json;
  try {
    json = jsonDecode(File(path).readAsStringSync());
  } on FormatException {
    throw const MarkerBackupFormatException();
  }
  return parseMarkerBackup(json);
}

/// גיבוי של המרקר המובנה או של התוסף הישן.
LegacyMarkerData parseMarkerBackup(Object? json) {
  if (json is Map && json['format'] == 'otzaria-marker-backup') {
    try {
      final data = parseLegacyMarkerBackup(json);
      if (data.highlights.length > MarkerTransfer.maxRecords) {
        throw const MarkerBackupTooLargeException();
      }
      return data;
    } on LegacyMarkerFormatException {
      throw const MarkerBackupFormatException();
    }
  }
  if (json is! Map ||
      json['format'] != MarkerTransfer.format ||
      json['schemaVersion'] is! int ||
      (json['schemaVersion'] as int) > MarkerTransfer.schemaVersion ||
      json['highlights'] is! List) {
    throw const MarkerBackupFormatException();
  }
  final raw = json['highlights'] as List;
  if (raw.length > MarkerTransfer.maxRecords) {
    throw const MarkerBackupTooLargeException();
  }
  final highlights = <MarkerHighlight>[];
  final ids = <String>{};
  var invalid = 0;
  for (final entry in raw) {
    try {
      if (entry is! Map) throw const FormatException('not an object');
      final highlight = MarkerHighlight.fromJson(
        Map<String, dynamic>.from(entry),
      );
      if (!ids.add(highlight.id)) throw const FormatException('duplicate id');
      highlights.add(highlight);
    } on FormatException {
      invalid++;
    }
  }
  final palette = json['palette'];
  final legacy = json['importedLegacy'];
  return LegacyMarkerData(
    highlights: highlights,
    palette: palette is Map ? MarkerPalette.fromJson(palette) : null,
    invalid: invalid,
    fromPlugin: false,
    importedLegacy: [
      if (legacy is List)
        for (final entry in legacy)
          if (entry is Map && entry['id'] is String && entry['book'] is String)
            (id: entry['id'] as String, book: entry['book'] as String),
    ],
  );
}

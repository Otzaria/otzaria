import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// קובץ בתיקיית המקור. [id] מזהה את המסמך ב-SAF; בתיקייה רגילה הוא null.
class PackageFileEntry {
  const PackageFileEntry({
    required this.name,
    required this.size,
    this.id,
    this.owner,
  });

  final String name;
  final int size;
  final String? id;

  /// התיקייה שבה הקובץ יושב, כשנמנה דרך [MergedPackageFolder].
  final PackageFolder? owner;
}

/// תיקייה שבה מונחים קובצי הספרייה (חבילת המסייע או הקבצים עצמם). המימושים
/// מחזיקים מחרוזות בלבד, ולכן ניתן להעביר אותם ל-isolate שפורס.
abstract class PackageFolder {
  const PackageFolder();

  /// הקבצים שבשורש התיקייה (בלי תתי-תיקיות).
  Future<List<PackageFileEntry>> list();

  /// שמות תתי-התיקיות שישירות בתיקייה.
  Future<List<String>> folderNames();

  /// תת-התיקייה [name], או null כשאינה קיימת.
  Future<PackageFolder?> child(String name);

  Stream<List<int>> openRead(PackageFileEntry entry);

  /// תיאור לתצוגה ולהודעות שגיאה.
  String get displayName;

  /// נתיב הקובץ ב-dart:io, או null כשהקריאה אינה דרך מערכת הקבצים.
  String? localPath(PackageFileEntry entry) => null;

  /// הקריאה עוברת בערוץ פלטפורמה, ולכן isolate צריך `RootIsolateToken`.
  bool get usesPlatformChannel => false;
}

class DirectoryPackageFolder extends PackageFolder {
  const DirectoryPackageFolder(this.path);

  final String path;

  @override
  String get displayName => path;

  @override
  Future<List<PackageFileEntry>> list() async {
    final entries = <PackageFileEntry>[];
    await for (final entity in Directory(path).list(followLinks: true)) {
      if (entity is! File) continue;
      entries.add(
        PackageFileEntry(
          name: p.basename(entity.path),
          size: await entity.length(),
        ),
      );
    }
    return entries;
  }

  @override
  Future<List<String>> folderNames() async => [
    await for (final entity in Directory(path).list(followLinks: true))
      if (entity is Directory) p.basename(entity.path),
  ];

  @override
  Future<PackageFolder?> child(String name) async {
    final dir = p.join(path, name);
    return await Directory(dir).exists() ? DirectoryPackageFolder(dir) : null;
  }

  @override
  String localPath(PackageFileEntry entry) => p.join(path, entry.name);

  @override
  Stream<List<int>> openRead(PackageFileEntry entry) =>
      File(localPath(entry)).openRead();
}

/// תיקייה שנבחרה ב-SAF באנדרואיד: ל-dart:io אין גישה אליה, והקריאה עוברת
/// בנתחים דרך `FolderImportChannel.kt`. מתוך isolate נדרש קודם
/// `BackgroundIsolateBinaryMessenger.ensureInitialized`.
class SafPackageFolder extends PackageFolder {
  const SafPackageFolder({
    required this.treeUri,
    required this.name,
    this.documentId,
  });

  final String treeUri;
  final String name;

  /// מזהה תת-תיקייה בתוך העץ; null — שורש העץ שנבחר.
  final String? documentId;

  static const _channel = MethodChannel('otzaria/folder_import');
  static const _chunkBytes = 4 << 20;

  @override
  String get displayName => name;

  @override
  bool get usesPlatformChannel => true;

  @override
  Future<List<PackageFileEntry>> list() async {
    final files = await _channel.invokeListMethod<Map>('listFiles', {
      'uri': treeUri,
      'parentId': documentId,
    });
    return [
      for (final file in files ?? const <Map>[])
        PackageFileEntry(
          name: file['name'] as String,
          size: file['size'] as int,
          id: file['id'] as String,
        ),
    ];
  }

  @override
  Future<List<String>> folderNames() async =>
      await _channel.invokeListMethod<String>('listFolders', {
        'uri': treeUri,
        'parentId': documentId,
      }) ??
      const [];

  @override
  Future<PackageFolder?> child(String name) async {
    final id = await _channel.invokeMethod<String>('childFolder', {
      'uri': treeUri,
      'parentId': documentId,
      'name': name,
    });
    return id == null
        ? null
        : SafPackageFolder(
            treeUri: treeUri,
            name: '${this.name}/$name',
            documentId: id,
          );
  }

  @override
  Stream<List<int>> openRead(PackageFileEntry entry) async* {
    final handle = await _channel.invokeMethod<int>('openDocument', {
      'uri': treeUri,
      'id': entry.id,
    });
    try {
      while (true) {
        final chunk = await _channel.invokeMethod<Uint8List>('readDocument', {
          'handle': handle,
          'max': _chunkBytes,
        });
        if (chunk == null || chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await _channel.invokeMethod<void>('closeDocument', {'handle': handle});
    }
  }
}

/// כמה תיקיות שמוצגות כתיקייה אחת — כרכי ZIP שכל אחד חולץ לתיקייה משלו.
/// קובץ שמופיע בכמה מהן באותו גודל נלקח פעם אחת; בגדלים שונים — הוא
/// מושמט מ-[list] ונמנה ב-[conflicts].
class MergedPackageFolder extends PackageFolder {
  const MergedPackageFolder(this.members, {required this.displayName});

  final List<PackageFolder> members;

  @override
  final String displayName;

  @override
  bool get usesPlatformChannel => members.any((m) => m.usesPlatformChannel);

  @override
  Future<List<PackageFileEntry>> list() async => (await _merge()).$1;

  /// שמות הקבצים שמופיעים בכמה תיקיות בגדלים שונים.
  Future<Set<String>> conflicts() async => (await _merge()).$2;

  Future<(List<PackageFileEntry>, Set<String>)> _merge() async {
    final byName = <String, PackageFileEntry>{};
    final conflicts = <String>{};
    for (final member in members) {
      for (final e in await member.list()) {
        final existing = byName[e.name];
        if (existing == null) {
          byName[e.name] = PackageFileEntry(
            name: e.name,
            size: e.size,
            id: e.id,
            owner: e.owner ?? member,
          );
        } else if (existing.size != e.size) {
          conflicts.add(e.name);
        }
      }
    }
    return (
      [
        for (final e in byName.values)
          if (!conflicts.contains(e.name)) e,
      ],
      conflicts,
    );
  }

  @override
  Future<List<String>> folderNames() async => {
    for (final member in members) ...await member.folderNames(),
  }.toList();

  @override
  Future<PackageFolder?> child(String name) async {
    final children = [
      for (final member in members) ?await member.child(name),
    ];
    if (children.length < 2) return children.firstOrNull;
    return MergedPackageFolder(children, displayName: '$displayName/$name');
  }

  @override
  String? localPath(PackageFileEntry entry) => _owner(entry).localPath(entry);

  @override
  Stream<List<int>> openRead(PackageFileEntry entry) =>
      _owner(entry).openRead(entry);

  PackageFolder _owner(PackageFileEntry entry) =>
      entry.owner ??
      (throw ArgumentError.value(entry.name, 'entry', 'לא נמנה מתיקייה זו'));
}

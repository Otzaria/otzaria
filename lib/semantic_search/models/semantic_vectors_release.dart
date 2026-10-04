import 'package:equatable/equatable.dart';

/// קובץ להורדה מתוך release הוקטורים, כפי שהמניפסט מתאר אותו.
class SemanticVectorsFile extends Equatable {
  /// שם הנכס ב-release, למשל `...-v30-base.oxv.zst` או `....part-000`.
  final String name;
  final String downloadUrl;
  final int size;

  /// SHA-256 של הקובץ כפי שהוא מורד (דחוס).
  final String sha256;

  /// מזהה הנכס ב-GitHub; משתנה בהעלאה מחדש — חלק מזהות ה-resume.
  final String assetId;

  const SemanticVectorsFile({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.sha256,
    required this.assetId,
  });

  @override
  List<Object?> get props => [name, downloadUrl, size, sha256, assetId];
}

/// release וקטורים שנמצא ב-SeforimLibrary עבור תג ספרייה.
class SemanticVectorsRelease extends Equatable {
  /// תג הספרייה, למשל `v30-20260930165019`.
  final String libraryTag;

  /// תג ה-release, `vectors-<libraryTag>`.
  final String releaseTag;

  /// גרסת הספרייה שהסט מביא אליה (`toLibraryVersion`).
  final int toLibraryVersion;

  /// `base`, `delta` או `compacted`.
  final String kind;

  /// טקסט המניפסט כפי שפורסם — נמסר להתקנה בדיוק כך.
  final String manifestJson;

  /// ה-SHA-256 של המניפסט מהערות ה-release; `null` כשלא פורסם.
  final String? publishedManifestSha256;

  /// הקבצים להורדה, לפי הסדר (חלקים מחוברים בסדר הזה).
  final List<SemanticVectorsFile> files;

  /// גודל ה-segment הפרוס — המקום שההתקנה תתפוס.
  final int segmentUncompressedSize;

  const SemanticVectorsRelease({
    required this.libraryTag,
    required this.releaseTag,
    required this.toLibraryVersion,
    required this.kind,
    required this.manifestJson,
    required this.publishedManifestSha256,
    required this.files,
    required this.segmentUncompressedSize,
  });

  /// סך הבתים להורדה.
  int get downloadSize => files.fold(0, (sum, file) => sum + file.size);

  /// שם ה-segment השלם: הקובץ היחיד, או שם החלקים בלי `.part-NNN`.
  String get segmentFileName => files.length == 1
      ? files.single.name
      : files.first.name.replaceFirst(RegExp(r'\.part-\d+$'), '');

  @override
  List<Object?> get props => [
    libraryTag,
    releaseTag,
    toLibraryVersion,
    kind,
    manifestJson,
    publishedManifestSha256,
    files,
    segmentUncompressedSize,
  ];
}

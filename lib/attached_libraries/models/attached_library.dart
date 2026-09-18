import 'package:equatable/equatable.dart';
import 'package:otzaria/models/book_source.dart';

/// איך המסד מצורף: קישור לקובץ במקומו, או עותק שהתוכנה מנהלת.
enum AttachedLibraryMode { link, copy }

/// היכן ספרי המסד מוצגים בעץ הספרייה.
enum AttachedLibraryPlacement {
  /// תחת `ספרים אישיים/<שם המסד>`.
  separateRoot,

  /// קטגוריות המסד מתמזגות לקטגוריות הספרייה לפי שם.
  mergeIntoLibrary,
}

enum AttachedLibraryStatus {
  ok,

  /// הקובץ אינו נגיש כרגע (כונן נשלף). ההגדרות נשמרות והספרים מוסתרים.
  unreachable,

  /// הקובץ אינו מסד ספרים תקין; הסיבה ב-[AttachedLibrary.problem].
  invalid,

  /// מסד אחר כבר מצורף עם אותו מזהה.
  duplicateSlug,
}

/// הסיבה שמסד נדחה או אינו תקין.
enum AttachedLibraryProblem {
  notFound,
  notSqlite,

  /// ליד הקובץ יש יומן שטרם הוחל (`-wal` או `-journal` חם) — תוכנה אחרת
  /// כותבת אליו או שנסגרה באמצע. במצב קישור אסור לכתוב לקובץ כדי להחיל אותו.
  pendingJournal,

  /// אין במסד טבלת `book`.
  noBooks,
  openFailed,
  duplicateSlug,
  copyFailed,
  alreadyAttached,
}

/// יכולות שמוצגות למשתמש בכרטיס המסד. נגזרות מ-DbCapabilities.
enum AttachedLibraryCapability {
  categories,
  toc,
  links,
  altToc,
  versions,
  authors,
  generations,
  acronyms,
  lineRef,
  defaultCommentators,
  externalLinks,
}

/// טביעת האצבע של הקובץ — שינוי בה מחייב בדיקה מחדש של המסד.
class AttachedLibraryFingerprint extends Equatable {
  final int size;
  final int modifiedMs;

  /// `schema_meta.db_version`, כשקיים.
  final String? dbVersion;

  const AttachedLibraryFingerprint({
    required this.size,
    required this.modifiedMs,
    this.dbVersion,
  });

  /// האם הקובץ בדיסק (גודל + זמן שינוי) שונה מהטביעה.
  bool fileDiffers({required int size, required int modifiedMs}) =>
      size != this.size || modifiedMs != this.modifiedMs;

  Map<String, dynamic> toJson() => {
    'size': size,
    'modifiedMs': modifiedMs,
    if (dbVersion != null) 'dbVersion': dbVersion,
  };

  static AttachedLibraryFingerprint? fromJson(Object? json) {
    if (json is! Map) return null;
    final size = json['size'];
    final modifiedMs = json['modifiedMs'];
    if (size is! int || modifiedMs is! int) return null;
    return AttachedLibraryFingerprint(
      size: size,
      modifiedMs: modifiedMs,
      dbVersion: json['dbVersion'] as String?,
    );
  }

  @override
  List<Object?> get props => [size, modifiedMs, dbVersion];
}

/// מסד ספרים מצורף בפורמט seforim.db.
///
/// הזהות ברשימה היא [path]; [slug] הוא זהות הספרים (`BookSource.attached`)
/// וייחודי רק בין מסדים במצב [AttachedLibraryStatus.ok].
class AttachedLibrary extends Equatable {
  final String slug;
  final String displayName;
  final String path;

  /// התיקייה שממנה צורף אוטומטית; null — יובא ידנית.
  final String? folderPath;
  final AttachedLibraryMode mode;
  final AttachedLibraryPlacement placement;
  final bool hidden;

  /// סדר ההצגה: קטן יותר מוצג קודם.
  final int priority;

  /// נפתח ב-URI immutable (מסד WAL / תיקייה בלי הרשאת כתיבה).
  final bool immutable;
  final AttachedLibraryFingerprint? fingerprint;
  final AttachedLibraryStatus status;
  final AttachedLibraryProblem? problem;
  final Set<AttachedLibraryCapability> capabilities;
  final int bookCount;
  final DateTime addedAt;

  const AttachedLibrary({
    required this.slug,
    required this.displayName,
    required this.path,
    this.folderPath,
    this.mode = AttachedLibraryMode.link,
    this.placement = AttachedLibraryPlacement.separateRoot,
    this.hidden = false,
    this.priority = 0,
    this.immutable = false,
    this.fingerprint,
    this.status = AttachedLibraryStatus.ok,
    this.problem,
    this.capabilities = const {},
    this.bookCount = 0,
    required this.addedAt,
  });

  bool get isImported => folderPath == null;
  bool get isOk => status == AttachedLibraryStatus.ok;

  /// ספרי המסד מוצגים בעץ הספרייה.
  bool get isVisibleInLibrary => isOk && !hidden;

  /// `imported` או `folder:<path>`.
  String get originKey =>
      folderPath == null ? 'imported' : 'folder:$folderPath';

  /// המקור של ספרי המסד, או null כשה-slug אינו חוקי.
  AttachedBookSource? get source => BookSource.isValidSlug(slug)
      ? BookSource.attached(slug) as AttachedBookSource
      : null;

  /// [clearProblem] מאפס את [problem] — `problem: null` לבדו פירושו "אל תשנה".
  AttachedLibrary copyWith({
    String? slug,
    String? displayName,
    String? path,
    AttachedLibraryMode? mode,
    AttachedLibraryPlacement? placement,
    bool? hidden,
    int? priority,
    bool? immutable,
    AttachedLibraryFingerprint? fingerprint,
    AttachedLibraryStatus? status,
    AttachedLibraryProblem? problem,
    bool clearProblem = false,
    Set<AttachedLibraryCapability>? capabilities,
    int? bookCount,
  }) {
    return AttachedLibrary(
      slug: slug ?? this.slug,
      displayName: displayName ?? this.displayName,
      path: path ?? this.path,
      folderPath: folderPath,
      mode: mode ?? this.mode,
      placement: placement ?? this.placement,
      hidden: hidden ?? this.hidden,
      priority: priority ?? this.priority,
      immutable: immutable ?? this.immutable,
      fingerprint: fingerprint ?? this.fingerprint,
      status: status ?? this.status,
      problem: clearProblem ? null : (problem ?? this.problem),
      capabilities: capabilities ?? this.capabilities,
      bookCount: bookCount ?? this.bookCount,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'displayName': displayName,
    'path': path,
    'origin': originKey,
    'mode': mode.name,
    'placement': placement.name,
    if (hidden) 'hidden': true,
    'priority': priority,
    if (immutable) 'immutable': true,
    if (fingerprint != null) 'fingerprint': fingerprint!.toJson(),
    'status': status.name,
    if (problem != null) 'problem': problem!.name,
    'capabilities': [for (final c in capabilities) c.name],
    'bookCount': bookCount,
    'addedAt': addedAt.toIso8601String(),
  };

  /// זורק על רשומה בלי השדות ההכרחיים; ערך לא מוכר בשדה אחר נופל לברירת מחדל.
  factory AttachedLibrary.fromJson(Map<String, dynamic> json) {
    final origin = json['origin'] as String? ?? 'imported';
    return AttachedLibrary(
      slug: json['slug'] as String,
      displayName: json['displayName'] as String? ?? json['slug'] as String,
      path: json['path'] as String,
      folderPath: origin.startsWith('folder:') ? origin.substring(7) : null,
      mode:
          _byName(AttachedLibraryMode.values, json['mode']) ??
          AttachedLibraryMode.link,
      placement:
          _byName(AttachedLibraryPlacement.values, json['placement']) ??
          AttachedLibraryPlacement.separateRoot,
      hidden: json['hidden'] == true,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      immutable: json['immutable'] == true,
      fingerprint: AttachedLibraryFingerprint.fromJson(json['fingerprint']),
      status:
          _byName(AttachedLibraryStatus.values, json['status']) ??
          AttachedLibraryStatus.ok,
      problem: _byName(AttachedLibraryProblem.values, json['problem']),
      capabilities: {
        for (final name in (json['capabilities'] as List? ?? const []))
          ?_byName(AttachedLibraryCapability.values, name),
      },
      bookCount: (json['bookCount'] as num?)?.toInt() ?? 0,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) =>
      values.where((v) => v.name == name).firstOrNull;

  @override
  List<Object?> get props => [
    slug,
    displayName,
    path,
    folderPath,
    mode,
    placement,
    hidden,
    priority,
    immutable,
    fingerprint,
    status,
    problem,
    capabilities,
    bookCount,
  ];
}

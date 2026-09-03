import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

/// תאריך עברי חלקי כפי שמגיע מה-API של תא שמע — כל רכיב עשוי להיות חסר.
class HebrewDate extends Equatable {
  final String? year;
  final String? month;
  final String? day;

  const HebrewDate({this.year, this.month, this.day});

  static HebrewDate? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final date = HebrewDate(
      year: json['year'] as String?,
      month: json['month'] as String?,
      day: json['day'] as String?,
    );
    return date.isEmpty ? null : date;
  }

  bool get isEmpty => year == null && month == null && day == null;

  /// תצוגה בסדר עברי מקובל: יום, חודש, שנה — רק הרכיבים הקיימים.
  String get display => [day, month, year].whereType<String>().join(' ');

  @override
  List<Object?> get props => [year, month, day];
}

/// ערך ביוגרפיה של רב אחד, כפי שפוענח מקובץ `biographies.tsb`.
class Biography extends Equatable {
  final int id;

  /// שם תצוגה מלא (תואר + שם + תואר סיום). מורכב בצינור הבנייה כשקיים,
  /// אחרת מורכב כאן משדות המסמך.
  final String name;

  final String? summary;
  final String? biographyShort;
  final String? generation;
  final List<String> appelations;
  final List<String> communities;
  final List<String> countries;
  final HebrewDate? birthHebrew;
  final HebrewDate? deathHebrew;

  const Biography({
    required this.id,
    required this.name,
    this.summary,
    this.biographyShort,
    this.generation,
    this.appelations = const [],
    this.communities = const [],
    this.countries = const [],
    this.birthHebrew,
    this.deathHebrew,
  });

  /// טקסט עברי משדה רב-לשוני בצורת `{"he": "...", "en": "..."}`.
  static String? _he(Object? field) {
    if (field is Map<String, dynamic>) {
      final he = field['he'];
      if (he is String && he.trim().isNotEmpty) return he.trim();
      final first = field.values.whereType<String>().firstOrNull;
      if (first != null && first.trim().isNotEmpty) return first.trim();
    }
    return null;
  }

  factory Biography.fromEntry(Map<String, dynamic> entry) {
    final doc = (entry['doc'] as Map<String, dynamic>?) ?? const {};
    final resolved = (entry['resolved'] as Map<String, dynamic>?) ?? const {};

    final appelations = ((doc['appelations'] as List?) ?? const [])
        .map(_he)
        .whereType<String>()
        .toList();

    var name = (entry['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      // סדר כמו באתר תא שמע: שם משפחה, אחריו הכינוי ("מיכל בת שאול"),
      // ורק בהיעדר שניהם שם האב — "בר"/"בת" לפי המין ("רב אדא בר אהבה").
      final father = doc['father'];
      final fatherName = father is Map<String, dynamic>
          ? _he(father['name'])
          : null;
      // שדה האב מגיע לעיתים כביטוי מוכן ("בת פוטיפרע") — אין להוסיף שוב.
      final hasPrefix =
          fatherName != null && RegExp(r'^ב[ןתר] ').hasMatch(fatherName);
      final sonOrDaughter = doc['isMale'] == false ? 'בת' : 'בר';
      name = [
        resolved['titlePre'] as String?,
        _he(doc['nameFirst']),
        _he(doc['nameLast']) ??
            appelations.firstOrNull ??
            (fatherName == null
                ? null
                : hasPrefix
                ? fatherName
                : '$sonOrDaughter $fatherName'),
        resolved['titlePost'] as String?,
      ].whereType<String>().join(' ');
    }
    // ערכים בודדים מגיעים ללא שם כלל אלא עם כינוי בלבד — בלעדיו השורה ריקה.
    if (name.trim().isEmpty) name = appelations.firstOrNull ?? '';

    List<String> strings(Object? value) => switch (value) {
      final List list => list.whereType<String>().toList(),
      _ => const [],
    };

    return Biography(
      id: entry['id'] as int,
      name: name,
      summary: _he(doc['summary']),
      biographyShort: _he(doc['biographyShort']),
      generation: resolved['generation'] as String?,
      appelations: appelations,
      communities: strings(resolved['communities']),
      countries: strings(resolved['countries']),
      birthHebrew: HebrewDate.fromJson(entry['birthHebrew']),
      deathHebrew: HebrewDate.fromJson(entry['deathHebrew']),
    );
  }

  @override
  List<Object?> get props => [id, name, summary, biographyShort];
}

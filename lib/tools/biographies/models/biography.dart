import 'package:equatable/equatable.dart';

/// Birth or death: Hebrew date, Gregorian year and place, each optional.
class LifeEvent extends Equatable {
  final String? hebrew;
  final String? gregorian;
  final String? place;

  const LifeEvent({this.hebrew, this.gregorian, this.place});

  static LifeEvent? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final event = LifeEvent(
      hebrew: _string(json['hebrew']),
      gregorian: _string(json['gregorian']),
      place: _string(json['place']),
    );
    return event.isEmpty ? null : event;
  }

  bool get isEmpty => hebrew == null && gregorian == null && place == null;

  /// "ד'תתצ"ח (1138), קורדובה" - only the parts that exist.
  String get display {
    final date = [?hebrew, if (gregorian != null) '($gregorian)'].join(' ');
    return [if (date.isNotEmpty) date, ?place].join(', ');
  }

  @override
  List<Object?> get props => [hebrew, gregorian, place];
}

/// A teacher, student or relative; [ref] is the id of their own entry.
class RelatedPerson extends Equatable {
  final String name;
  final String? relation;
  final String? ref;

  const RelatedPerson({required this.name, this.relation, this.ref});

  static RelatedPerson? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = _string(json['name']);
    if (name == null) return null;
    return RelatedPerson(
      name: name,
      relation: _string(json['relation']),
      ref: _string(json['ref']),
    );
  }

  /// "אביו: רבי מימון הדיין", or the name alone.
  String get display => relation == null ? name : '$relation: $name';

  @override
  List<Object?> get props => [name, relation, ref];
}

class BiographyWork extends Equatable {
  final String title;
  final String? description;

  /// Exact titles of the work's book in the library, as the biographies data
  /// maps them; several titles are the volumes of one work.
  final List<String> books;

  const BiographyWork({
    required this.title,
    this.description,
    this.books = const [],
  });

  static BiographyWork? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final title = _string(json['title']);
    if (title == null) return null;
    return BiographyWork(
      title: title,
      description: _string(json['description']),
      books: _strings(json['books']),
    );
  }

  String get display => description == null ? title : '$title - $description';

  @override
  List<Object?> get props => [title, description, books];
}

/// A source page an entry was written from; [credit] keys
/// [BiographiesBundle.credits].
class BiographySource extends Equatable {
  final String credit;
  final String? title;
  final String url;

  const BiographySource({required this.credit, this.title, required this.url});

  static BiographySource? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final credit = _string(json['credit']);
    final url = _string(json['url']);
    if (credit == null || url == null) return null;
    return BiographySource(
      credit: credit,
      title: _string(json['title']),
      url: url,
    );
  }

  @override
  List<Object?> get props => [credit, title, url];
}

/// One card of the "Toldot Gedolei Yisrael" bundle (`biographies-app`).
class Biography extends Equatable {
  final String id;
  final String name;
  final String era;

  /// Display label of [era], resolved from the bundle's era list.
  final String? eraLabel;

  final String? honorific;
  final List<String> knownAs;
  final String? generation;
  final List<String> region;
  final LifeEvent? born;
  final LifeEvent? died;
  final String? buried;
  final List<String> roles;
  final List<RelatedPerson> teachers;
  final List<RelatedPerson> students;
  final List<RelatedPerson> family;
  final List<BiographyWork> works;
  final String? mentionedIn;
  final String? summary;
  final String? remember;
  final List<BiographySource> sources;

  const Biography({
    required this.id,
    required this.name,
    this.era = '',
    this.eraLabel,
    this.honorific,
    this.knownAs = const [],
    this.generation,
    this.region = const [],
    this.born,
    this.died,
    this.buried,
    this.roles = const [],
    this.teachers = const [],
    this.students = const [],
    this.family = const [],
    this.works = const [],
    this.mentionedIn,
    this.summary,
    this.remember,
    this.sources = const [],
  });

  /// Throws [FormatException] when the entry has no id or name.
  factory Biography.fromJson(
    Map<String, dynamic> json, {
    Map<String, String> eraLabels = const {},
  }) {
    final id = _string(json['id']);
    final name = _string(json['name']);
    if (id == null || name == null) {
      throw const FormatException('Biography entry without an id or a name');
    }
    final era = _string(json['era']) ?? '';
    return Biography(
      id: id,
      name: name,
      era: era,
      eraLabel: eraLabels[era],
      honorific: _string(json['honorific']),
      knownAs: _strings(json['known_as']),
      generation: _string(json['generation']),
      region: _strings(json['region']),
      born: LifeEvent.fromJson(json['born']),
      died: LifeEvent.fromJson(json['died']),
      buried: _string(json['buried']),
      roles: _strings(json['roles']),
      teachers: _list(json['teachers'], RelatedPerson.fromJson),
      students: _list(json['students'], RelatedPerson.fromJson),
      family: _list(json['family'], RelatedPerson.fromJson),
      works: _list(json['works'], BiographyWork.fromJson),
      mentionedIn: _string(json['mentioned_in']),
      summary: _string(json['summary']),
      remember: _string(json['remember']),
      sources: _list(json['sources'], BiographySource.fromJson),
    );
  }

  /// Name with the honorific, as the card title shows it.
  String get fullName => honorific == null ? name : '$name $honorific';

  @override
  List<Object?> get props => [id, name, era, summary];
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _strings(Object? value) => switch (value) {
  final List list => list.map(_string).whereType<String>().toList(),
  _ => const [],
};

List<T> _list<T>(Object? value, T? Function(Object?) parse) => switch (value) {
  final List list => list.map(parse).whereType<T>().toList(),
  _ => const [],
};

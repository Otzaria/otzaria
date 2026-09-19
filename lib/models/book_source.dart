/// המקור של ספר: הספרייה הרשמית (seforim.db), ספר אישי (user_books.db), או
/// מסד מצורף שזוהה לפי slug.
///
/// `wireKey` הוא הצורה היציבה לשמירה ולהעברה: `o`, `u`, או `d:<slug>`.
sealed class BookSource {
  const BookSource();

  static const BookSource official = OfficialBookSource._();
  static const BookSource user = UserBookSource._();

  /// מסד מצורף. [slug] חייב לעבור את [isValidSlug].
  factory BookSource.attached(String slug) {
    if (!isValidSlug(slug)) {
      throw ArgumentError.value(slug, 'slug', 'Invalid attached library slug');
    }
    return AttachedBookSource._(slug);
  }

  /// ספר אישי או רשמי לפי הדגל הישן `isUserBook`.
  static BookSource fromUserFlag(bool isUserBook) =>
      isUserBook ? user : official;

  static final RegExp _slugPattern = RegExp(
    r'^[\p{L}\p{N}._-]{1,64}$',
    unicode: true,
  );

  /// slug מותר רק באותיות, ספרות ו-`._-`: הוא נכנס למפתחות שמופרדים ב-`|` וב-`:`.
  static bool isValidSlug(String slug) => _slugPattern.hasMatch(slug);

  /// מפענח [wireKey]; מחזיר null לערך לא מוכר או ל-slug לא חוקי.
  static BookSource? tryParse(String? wireKey) {
    switch (wireKey) {
      case 'o':
        return official;
      case 'u':
        return user;
    }
    if (wireKey != null && wireKey.startsWith('d:')) {
      final slug = wireKey.substring(2);
      if (isValidSlug(slug)) return AttachedBookSource._(slug);
    }
    return null;
  }

  /// המקור מתוך JSON של ספר/קישור: `source` כשקיים, אחרת הדגל הישן
  /// [legacyUserFlagKey] (JSON שנשמר לפני שהיה `source`).
  static BookSource fromJson(
    Map<dynamic, dynamic> json, {
    String key = 'source',
    String legacyUserFlagKey = 'isUserBook',
  }) {
    final raw = json[key];
    final parsed = tryParse(raw is String ? raw : null);
    if (parsed != null) return parsed;
    return fromUserFlag(json[legacyUserFlagKey] == true);
  }

  String get wireKey;

  bool get isOfficial => false;
  bool get isUser => false;
  bool get isAttached => false;

  /// ה-slug של מסד מצורף, או null.
  String? get attachedSlug => null;

  /// סיומת המקור במפתחות זהות (סימניות, היסטוריה, טאבים). לספר רשמי אין
  /// סיומת, כדי שמפתחות שכבר נשמרו לא ישתנו.
  String get identitySuffix;

  /// סדר ברירת המחדל בין המקורות: רשמי, אישי, מצורף.
  int get rank;

  @override
  String toString() => 'BookSource($wireKey)';
}

final class OfficialBookSource extends BookSource {
  const OfficialBookSource._();

  @override
  String get wireKey => 'o';

  @override
  bool get isOfficial => true;

  @override
  String get identitySuffix => '';

  @override
  int get rank => 0;
}

final class UserBookSource extends BookSource {
  const UserBookSource._();

  @override
  String get wireKey => 'u';

  @override
  bool get isUser => true;

  @override
  String get identitySuffix => kUserBookIdentitySuffix;

  @override
  int get rank => 1;
}

final class AttachedBookSource extends BookSource {
  const AttachedBookSource._(this.slug);

  final String slug;

  @override
  String get wireKey => 'd:$slug';

  @override
  bool get isAttached => true;

  @override
  String? get attachedSlug => slug;

  @override
  String get identitySuffix => '|src:d:$slug';

  @override
  int get rank => 2;

  @override
  bool operator ==(Object other) =>
      other is AttachedBookSource && other.slug == slug;

  @override
  int get hashCode => Object.hash(AttachedBookSource, slug);
}

/// סיומת המקור במפתחות זהות של ספר אישי.
const kUserBookIdentitySuffix = '|src:u';

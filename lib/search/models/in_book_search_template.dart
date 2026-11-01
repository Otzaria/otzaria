import 'package:equatable/equatable.dart';
import 'package:otzaria/search/models/search_match_policy.dart';

/// ערך ברירת המחדל באירוע משמר תבנית; null מפורש מסיר אותה.
const Object preserveInBookSearchTemplate = Object();

/// תבנית שנבחרה לחיפוש חדש, בלי תלות בהעדפות שישתנו אחר כך.
class InBookSearchTemplate extends Equatable {
  InBookSearchTemplate({
    Map<String, bool>? wordDefaults,
    required this.requestedPolicy,
  }) : wordDefaults = wordDefaults == null
           ? null
           : Map.unmodifiable(wordDefaults);

  final Map<String, bool>? wordDefaults;
  final SearchMatchPolicy requestedPolicy;

  Map<String, dynamic> toJson() => {
    if (wordDefaults != null) 'wordDefaults': wordDefaults,
    'requestedPolicy': requestedPolicy.toJson(),
  };

  static InBookSearchTemplate? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final defaults = value['wordDefaults'];
    if (defaults != null && defaults is! Map) return null;
    return InBookSearchTemplate(
      wordDefaults: defaults is! Map
          ? null
          : {
              for (final entry in defaults.entries)
                if (entry.key is String && entry.value is bool)
                  entry.key as String: entry.value as bool,
            },
      requestedPolicy: SearchMatchPolicy.fromJson(value['requestedPolicy']),
    );
  }

  @override
  List<Object?> get props => [wordDefaults, requestedPolicy];
}

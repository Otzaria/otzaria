import 'dart:collection';

import 'package:otzaria/plugins/declarative/models/declarative_program.dart';

Map<String, dynamic> requiredMap(
  Object? value,
  String context, {
  required String code,
}) {
  if (value is! Map) {
    throw DeclarativeProgramException(code, '$context must be an object');
  }
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw DeclarativeProgramException(code, '$context keys must be strings');
  }
}

List<dynamic> requiredList(
  Object? value,
  String context, {
  required String code,
}) {
  if (value is! List) {
    throw DeclarativeProgramException(code, '$context must be an array');
  }
  return value;
}

/// U+0000–U+001F או U+007F.
bool hasControlChars(String value) {
  for (final unit in value.codeUnits) {
    if (unit < 0x20 || unit == 0x7F) return true;
  }
  return false;
}

final RegExp _referencePathPart = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

/// רכיבי [path] המופרדים בנקודה; כל רכיב חייב להיות מזהה.
List<String> referencePathParts(String path, String context) {
  final parts = path.split('.');
  if (parts.any((part) => !_referencePathPart.hasMatch(part))) {
    throw DeclarativeProgramException(
      'declarative.invalid_reference',
      '$context contains an invalid path',
    );
  }
  return parts;
}

/// הערך שבנתיב [path] בתוך [root], או null כשרכיב כלשהו חסר.
Object? readValuePath(Object? root, String path) {
  Object? current = root;
  for (final part in path.split('.')) {
    if (current is Map && current.containsKey(part)) {
      current = current[part];
    } else {
      return null;
    }
  }
  return current;
}

/// null, מחרוזת, רשימה ומפה ריקות נחשבים ריקים.
bool isNotEmptyValue(Object? value) {
  if (value is String) return value.isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return value != null;
}

Object? deepCopyValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key: deepCopyValue(entry.value),
    };
  }
  if (value is List) return value.map(deepCopyValue).toList();
  return value;
}

void assertOnlyKeys(
  Map<String, dynamic> value,
  Set<String> allowed,
  String context,
) {
  final unknown = value.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw DeclarativeProgramException(
      'declarative.unknown_field',
      '$context contains unsupported fields: ${unknown.join(', ')}',
    );
  }
}

Map<String, dynamic> deepFreeze(Map<String, dynamic> value) {
  return UnmodifiableMapView({
    for (final entry in value.entries) entry.key: deepFreezeValue(entry.value),
  });
}

Object? deepFreezeValue(Object? value) {
  if (value is Map) return deepFreeze(Map<String, dynamic>.from(value));
  if (value is List) return List.unmodifiable(value.map(deepFreezeValue));
  return value;
}

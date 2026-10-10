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

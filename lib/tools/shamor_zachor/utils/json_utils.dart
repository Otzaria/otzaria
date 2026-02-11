/// Utilities for safe extraction of typed values from JSON-like structures.
class JsonUtils {
  /// Safely read a string value; returns empty string on null or mismatched type.
  static String asString(dynamic value) => value is String ? value : '';

  /// Safely read an integer; accepts numeric strings as well.
  static int asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  /// Safely read a numeric value; accepts numeric strings as well.
  static num asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value) ?? 0;
    }
    return 0;
  }

  /// Safely convert a dynamic map into a string-keyed map.
  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}

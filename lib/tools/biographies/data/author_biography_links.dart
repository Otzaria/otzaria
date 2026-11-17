import 'dart:convert';

/// The editorial crosswalk from exact catalog author names to biography IDs.
abstract final class AuthorBiographyLinks {
  static const fileName = 'author_biographies.json';
  static const assetKey = 'assets/bio/$fileName';
  static const downloadUrl =
      'https://raw.githubusercontent.com/Otzaria/otzaria-library/main/$fileName';

  static Map<String, String> decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json['authors'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported author biography mapping');
    }
    final authors = json['authors'] as Map<String, dynamic>;
    return Map.unmodifiable(
      authors.map((name, id) {
        if (name.isEmpty ||
            name != name.trim() ||
            id is! String ||
            id.isEmpty ||
            id != id.trim()) {
          throw const FormatException('Invalid author biography mapping');
        }
        return MapEntry(name, id);
      }),
    );
  }
}

/// Constants for link connection types
class LinkTypes {
  LinkTypes._();

  /// Commentary link type - indicates a commentary relationship
  static const String commentary = 'COMMENTARY';

  /// Targum link type - indicates a translation/targum relationship
  static const String targum = 'TARGUM';

  /// Reference link type - indicates a general reference
  static const String reference = 'REFERENCE';

  /// Checks if a connection type is a commentary or targum
  static bool isCommentaryOrTargum(String? connectionType) {
    return connectionType == commentary || connectionType == targum;
  }
}

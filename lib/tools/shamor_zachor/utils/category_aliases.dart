/// Utility for mapping legacy category names to their new display names
/// and resolving aliases during cache migration.
class CategoryAliases {
  static const Map<String, String> oldToNew = {
    'תנך': 'תנ"ך',
    'ש"ס': 'תלמוד בבלי',
    'ירושלמי': 'תלמוד ירושלמי',
  };

  /// Return the normalized (new) name for a category, or the original
  /// if it is already using the new naming.
  static String normalize(String categoryName) {
    return oldToNew[categoryName] ?? categoryName;
  }

  /// Return legacy aliases for a given new category name.
  static List<String> legacyAliasesForNew(String newName) {
    switch (newName) {
      case 'תנ"ך':
        return const ['תנך'];
      case 'תלמוד בבלי':
        return const ['ש"ס'];
      case 'תלמוד ירושלמי':
        return const ['ירושלמי'];
      default:
        return const [];
    }
  }
}

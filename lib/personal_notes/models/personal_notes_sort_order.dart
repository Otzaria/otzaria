import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

enum PersonalNotesSortOrder {
  bookLocation,
  newestCreated,
  oldestCreated,
  lastUpdated;

  String get label => switch (this) {
    bookLocation => 'לפי ספר ומיקום',
    newestCreated => 'החדשות ביותר תחילה',
    oldestCreated => 'הוותיקות ביותר תחילה',
    lastUpdated => 'עודכנו לאחרונה',
  };

  bool get usesCreationDate => this == newestCreated || this == oldestCreated;

  int compare(PersonalNote a, PersonalNote b) {
    final dateComparison = switch (this) {
      bookLocation => 0,
      newestCreated => b.createdAt.compareTo(a.createdAt),
      oldestCreated => a.createdAt.compareTo(b.createdAt),
      lastUpdated => b.updatedAt.compareTo(a.updatedAt),
    };
    if (dateComparison != 0) return dateComparison;
    final bookComparison = a.bookId.compareTo(b.bookId);
    if (bookComparison != 0) return bookComparison;
    final lineComparison = (a.lineNumber ?? 0).compareTo(b.lineNumber ?? 0);
    if (lineComparison != 0) return lineComparison;
    final createdComparison = a.createdAt.compareTo(b.createdAt);
    if (createdComparison != 0) return createdComparison;
    return a.id.compareTo(b.id);
  }
}

const _sortOrderKey = 'key-personal-notes-sort-order';

PersonalNotesSortOrder loadPersonalNotesSortOrder() {
  final saved = Settings.getValue<String>(_sortOrderKey);
  return PersonalNotesSortOrder.values.firstWhere(
    (order) => order.name == saved,
    orElse: () => PersonalNotesSortOrder.bookLocation,
  );
}

Future<void> savePersonalNotesSortOrder(PersonalNotesSortOrder order) =>
    Settings.setValue<String>(_sortOrderKey, order.name);

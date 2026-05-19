// Adapters to convert between otzaria models and migration models
// This allows seamless integration between the existing codebase and the new database layer

import 'package:otzaria/models/books.dart' as otzaria_models;
import 'line.dart' as migration_models;
import 'toc_entry.dart' as migration_models;

/// Converts a migration TocEntry to an otzaria TocEntry
otzaria_models.TocEntry migrationTocToOtzariaToc(
  migration_models.TocEntry migrationToc,
  otzaria_models.TocEntry? parent,
) {
  final otzariaToc = otzaria_models.TocEntry(
    text: migrationToc.text,
    index: migrationToc.lineIndex ?? 0,
    level: migrationToc.level,
    parent: parent,
  );

  return otzariaToc;
}

/// Converts a list of migration Lines to a single text string
String migrationLinesToText(List<migration_models.Line> lines) {
  return lines.map((line) => line.content).join('\n');
}

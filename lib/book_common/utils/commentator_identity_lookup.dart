import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// הזהויות של [titles] שהן כותרות ספרים במסד הרשמי; כותרת שאינה ספר לא
/// מוחזרת. השאילתה רצה ב-worker, ובלעדיו ב-isolate זמני.
Future<Map<String, CommentatorIdentity>> lookupCommentatorIdentities(
  Iterable<String> titles,
) async {
  final wanted = titles.where((title) => title.trim().isNotEmpty).toSet();
  final provider = SqliteDataProvider.instance;
  if (wanted.isEmpty || !provider.isInitialized || provider.dbPath.isEmpty) {
    return const {};
  }

  final List rows;
  try {
    rows =
        await DbReadWorker.batched('commentatorIdentities', {
              'dbPath': provider.dbPath,
              'titles': wanted.toList(),
            })
            as List;
  } on Object catch (error, stackTrace) {
    // הזהות רק מעשירה את ההתאמה; בלעדיה היא נופלת לשם הבסיס.
    debugPrint('Commentator identities lookup failed: $error\n$stackTrace');
    return const {};
  }

  final identities = <String, CommentatorIdentity>{};
  for (final row in rows.cast<Map>()) {
    final title = row['title'] as String;
    final existing = identities[title];
    if (existing?.collectiveKey != null) continue;
    identities[title] = CommentatorIdentity(
      collectiveTitle: row['collectiveTitleHe'] as String?,
      baseBookTitle: row['baseBookTitle'] as String?,
    );
  }
  return identities;
}

/// [known] בתוספת הזהויות של הבחירות השמורות שאינן בו, כדי לזהות בחירה ישנה
/// שנשמרה כשם מלא של ספר ("יכין מקואות").
Future<Map<String, CommentatorIdentity>> withSelectionIdentities(
  Map<String, CommentatorIdentity> known,
  Iterable<String> selections,
) async {
  final missing = selections.where((title) => !known.containsKey(title));
  final found = await lookupCommentatorIdentities(missing);
  return found.isEmpty ? known : {...known, ...found};
}

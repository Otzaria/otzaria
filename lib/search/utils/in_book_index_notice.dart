import 'package:otzaria/core/messages/library_messages.dart';

/// ההודעה כשחיפוש בספר דרך המנוע החזיר 0 תוצאות והספר כלל אינו באינדקס.
/// בלעדיה "אין תוצאות" מסתיר מהמשתמש את הסיבה האמיתית.
String? inBookMissingFromIndexNotice({
  required String? indexedFilePath,
  required bool indexInitialized,
  required Set<String> indexedFilePaths,
  bool excludedByIndexMode = false,
}) {
  if (indexedFilePath == null || indexedFilePath.isEmpty) return null;
  if (!indexInitialized) return null;
  if (indexedFilePaths.contains(indexedFilePath)) return null;
  return excludedByIndexMode
      ? LibraryMessages.personalBookNotInSearchIndex
      : LibraryMessages.bookNotInSearchIndex;
}

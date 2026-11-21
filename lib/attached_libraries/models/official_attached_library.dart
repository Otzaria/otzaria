import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';

/// מסד אישי שאוצריא מפרסמת. האמון בו נקבע רק לפי הכתובת והמפתח שכאן,
/// ולעולם לא לפי מה שכתוב בקובץ המסד.
class OfficialAttachedLibrary {
  const OfficialAttachedLibrary({
    required this.libraryId,
    required this.displayName,
    required this.manifestUrl,
    required this.publicKey,
  });

  final String libraryId;
  final String displayName;
  final String manifestUrl;

  /// מפתח ed25519 ציבורי ב-base64. ערך לא תקין ⇒ הרשומה אינה פעילה.
  final String publicKey;

  /// null כשהמפתח או הכתובת אינם תקינים: אין הצעה ואין עדכון.
  AttachedLibraryUpdateSource? get source =>
      AttachedLibraryUpdateSource.fromMeta(
        libraryId: libraryId,
        manifestUrl: manifestUrl,
        publicKey: publicKey,
      );

  bool get isActive => source != null;
}

/// המפתח הציבורי של "מחברי זמננו". החלפתו מחייבת גרסת תוכנה חדשה.
const String zmanenuPublicKey = 'SSCyhGfqGpA2/QY4Abl4t7a7ES9coCEPE9+o7RwTrl0=';

abstract final class OfficialAttachedLibraries {
  static const List<OfficialAttachedLibrary> builtIn = [
    OfficialAttachedLibrary(
      libraryId: 'otzaria.zmanenu',
      displayName: 'מחברי זמננו',
      manifestUrl:
          'https://github.com/Otzaria/zmanenu-library/releases/latest/download/manifest.json',
      publicKey: zmanenuPublicKey,
    ),
  ];

  static List<OfficialAttachedLibrary> _catalog = builtIn;

  static List<OfficialAttachedLibrary> get catalog => _catalog;

  /// null מחזיר את הרשימה המובנית.
  @visibleForTesting
  static set catalogForTesting(List<OfficialAttachedLibrary>? catalog) =>
      _catalog = catalog ?? builtIn;

  static OfficialAttachedLibrary? byId(String libraryId) =>
      _catalog.where((entry) => entry.libraryId == libraryId).firstOrNull;
}

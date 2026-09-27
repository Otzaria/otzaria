import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_author_table.dart';

/// קריאת טבלת המחברים מארכיון הספרים של ההתקנה.
///
/// הארכיון הוא קובץ של כ-2GB, אבל נקראים ממנו רק ספריית המכל (כ-40KB)
/// וקובצי הטבלה — הגדול שבהם 20KB ב-CD25.
class ResponsaAuthorTableReader {
  ResponsaAuthorTableReader._();

  /// מעל הגודל הזה קובץ אינו טבלה של רשומות קצרות, והמבנה שונה ממה
  /// שחשבנו. חסם שמונע קריאה של מאות מגה-בתים לזיכרון בגלל ספרייה שגויה.
  static const int _maxMemberBytes = 1 << 20;

  /// הטבלה של [installation], או [ResponsaAuthorTable.empty] כשאין ארכיון
  /// (התקנה חלקית שההתקן שלה אינו מחובר) או שהמבנה אינו מוכר. אף אחד
  /// מאלה אינו סיבה לעצור בנייה: הביבליוגרפיה נשארת נסיגה.
  static ResponsaAuthorTable forInstallation(
    ResponsaInstallation installation,
  ) {
    final archive = installation.archivePath;
    return archive == null ? ResponsaAuthorTable.empty : forArchive(archive);
  }

  @visibleForTesting
  static ResponsaAuthorTable forArchive(String archivePath) {
    RandomAccessFile? file;
    try {
      file = File(archivePath).openSync();
      final length = file.lengthSync();
      final head = file.readSync(2);
      if (head.length < 2) return ResponsaAuthorTable.empty;
      final count = head[0] | (head[1] << 8);
      file.setPositionSync(0);
      final directory = ResponsaAuthorTable.parseDirectory(
        file.readSync(2 + count * ResponsaAuthorTable.directoryEntrySize),
        length,
      );
      if (directory == null) {
        debugPrint('ResponsaAuthorTable: מבנה לא מוכר ב-$archivePath');
        return ResponsaAuthorTable.empty;
      }
      final members = <String, Uint8List>{};
      for (final entry in directory) {
        if (!ResponsaAuthorTable.isTableMember(entry.name)) continue;
        if (entry.size > _maxMemberBytes) continue;
        file.setPositionSync(entry.offset);
        members[entry.name] = file.readSync(entry.size);
      }
      final table = ResponsaAuthorTable.parse(members);
      debugPrint(
        'ResponsaAuthorTable: ${table.authorCount} מחברים '
        'מתוך ${members.length} קבצים',
      );
      return table;
    } catch (error) {
      debugPrint('ResponsaAuthorTable: $error');
      return ResponsaAuthorTable.empty;
    } finally {
      file?.closeSync();
    }
  }
}

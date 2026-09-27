import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_author_table.dart';

/// קריאת טבלת המחברים מארכיון הספרים (כ-2GB) של ההתקנה.
/// נקראים ממנו רק ספריית המכל וקובצי הטבלה, לא הארכיון כולו.
class ResponsaAuthorTableReader {
  ResponsaAuthorTableReader._();

  /// חסם: ספרייה שגויה לא תגרום לקריאת מאות מגה-בתים לזיכרון.
  static const int _maxMemberBytes = 1 << 20;

  /// [ResponsaAuthorTable.empty] כשאין ארכיון או שהמבנה לא מוכר - לא עוצרים
  /// בנייה בגלל זה, הביבליוגרפיה נשארת נסיגה.
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

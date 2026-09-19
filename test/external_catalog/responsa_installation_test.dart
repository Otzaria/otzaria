import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';

/// זיהוי המהדורה וטביעת האצבע של ההתקנה.
///
/// **אין כאן רשימת מהדורות נתמכות.** מספר המהדורה נקרא מכל מקור שיש
/// ואינו מסונן מול רשימה: מהדורה שתצא מחר צריכה להתגלות בלי שינוי קוד.
void main() {
  group('מספר המהדורה מכל מקור', () {
    test('שם תיקיית התקנה', () {
      expect(ResponsaInstallationDiscovery.versionFromText('ResponsaCD25'), 25);
      expect(ResponsaInstallationDiscovery.versionFromText('ResponsaCD31'), 31);
      // מהדורה שאינה קיימת היום מתגלה באותה מידה.
      expect(
        ResponsaInstallationDiscovery.versionFromText('ResponsaCD 40'),
        40,
      );
    });

    test('DisplayName בעברית מה-Registry', () {
      expect(
        ResponsaInstallationDiscovery.versionFromText('ResponsaCD25 גירסה 25'),
        25,
      );
      expect(
        ResponsaInstallationDiscovery.versionFromText('פרוייקט השו"ת גירסה 29'),
        29,
      );
    });

    test('כותרת החלון של מופע חי', () {
      // המקור האמין ביותר: הוא מגיע מהתוכנה עצמה ולכן עובד גם בהתקנה
      // שהועתקה או ששמה שונה.
      expect(
        ResponsaInstallationDiscovery.versionFromWindowTitle(
          'פרוייקט השו"ת : גירסה 25',
        ),
        25,
      );
      expect(
        ResponsaInstallationDiscovery.versionFromWindowTitle('Responsa 27'),
        27,
      );
    });

    test('טקסט בלי מספר אינו ממציא מספר', () {
      expect(ResponsaInstallationDiscovery.versionFromText('ResponsaCD'), null);
      expect(ResponsaInstallationDiscovery.versionFromText(null), null);
      expect(ResponsaInstallationDiscovery.versionFromText(''), null);
    });
  });

  group('טביעת אצבע', () {
    ResponsaFingerprint print({
      int? version = 25,
      String install = r'C:\Program Files (x86)\ResponsaCD25',
      int? size = 2140586529,
    }) => ResponsaFingerprint(
      version: version,
      installPath: install,
      file00Size: size,
    );

    test('זהות מלאה מתאימה', () {
      expect(print().matches(print()), isTrue);
    });

    test('נתיב התקנה שונה — אינו מתאים', () {
      expect(print().matches(print(install: r'E:\ResponsaCD25')), isFalse);
    });

    test('גרסה שונה — אינה מתאימה', () {
      expect(print().matches(print(version: 29)), isFalse);
    });

    test('שדה שחסר באחד הצדדים אינו מכשיל', () {
      // אחרת קטלוג שנבנה לפני שנוסף שדה היה נפסל רק בגלל הוספתו —
      // וזה קורה בדיוק בהתקנה חלקית, שבה הארכיון אינו ליד קובץ ההרצה.
      expect(print().matches(print(size: null)), isTrue);
      expect(print(size: null).matches(print()), isTrue);
    });

    test('לוכסן סופי ואותיות גדולות אינם מבדילים', () {
      expect(
        print().matches(
          print(install: r'c:\program files (x86)\responsacd25\'),
        ),
        isTrue,
      );
    });

    test('מטא-דאטה עוברת הלוך ושוב', () {
      final restored = ResponsaFingerprint.fromMeta(print().toMeta());
      expect(restored, isNotNull);
      expect(restored!.matches(print()), isTrue);
    });
  });

  group('התקנה חלקית שנטענת מהתקן נשלף', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('responsa_partial');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    ResponsaInstallation installationAt(String directory) =>
        ResponsaInstallation(
          version: null,
          installPath: directory,
          displayName: 'partial',
          source: 'filesystem',
        );

    test('תיקייה עם קובץ ההרצה היא התקנה, יהיה שמה אשר יהיה', () {
      File(p.join(root.path, 'RESPONSA.exe')).writeAsStringSync('');
      expect(installationAt(root.path).exists, isTrue);
    });

    test('אתר הנתונים נקרא מ-Responsa.env', () {
      final data = Directory(p.join(root.path, 'elsewhere'))
        ..createSync(recursive: true);
      File(p.join(root.path, 'Responsa.env')).writeAsStringSync(
        ['Something=1', 'DataLocation=${data.path}', 'Other=2'].join('\r\n'),
      );
      expect(installationAt(root.path).dataLocation, data.path);
    });

    test('הארכיון נמצא באתר הנתונים כשאינו ליד קובץ ההרצה', () {
      // זה בדיוק מצב ההתקנה החלקית: קובץ ההרצה על ההתקן הנשלף,
      // והמאגר במקום אחר לגמרי.
      final data = Directory(p.join(root.path, 'elsewhere'))
        ..createSync(recursive: true);
      Directory(p.join(data.path, 'DB')).createSync(recursive: true);
      File(p.join(data.path, 'DB', 'FILE00')).writeAsStringSync('');
      File(
        p.join(root.path, 'Responsa.env'),
      ).writeAsStringSync('DataLocation=${data.path}');
      expect(
        installationAt(root.path).archivePath,
        p.join(data.path, 'DB', 'FILE00'),
      );
    });

    test('אין Responsa.env — אין אתר נתונים, וזה מצב חוקי', () {
      expect(installationAt(root.path).dataLocation, isNull);
      expect(installationAt(root.path).archivePath, isNull);
    });
  });
}

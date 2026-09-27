import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_author_table_reader.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_builder.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_writer.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_author_table.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_bibliography.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_structure.dart';
import 'package:path/path.dart' as p;

/// רשומה של 73 בתים: מזהה big-endian וטקסט CP862 מרופד.
Uint8List record(int id, String text) {
  final bytes = Uint8List(ResponsaAuthorTable.recordSize);
  bytes[0] = id >> 8;
  bytes[1] = id & 0xFF;
  var at = 2;
  for (final unit in text.codeUnits) {
    bytes[at++] = switch (unit) {
      >= 0x05D0 && <= 0x05EA => 0x80 + unit - 0x05D0,
      // הסוגריים בארכיון הפוכים, כמו בכל טקסט DOS ויזואלי.
      0x28 => 0x29,
      0x29 => 0x28,
      _ => unit,
    };
  }
  return bytes;
}

Uint8List table(List<Uint8List> records) =>
    Uint8List.fromList([for (final r in records) ...r]);

void main() {
  group('bookIdOf', () {
    test('המזהה הוא המילה הנמוכה של lParam בסדר בתים הפוך', () {
      // `אבן האזל`: 0x46109 בעץ, 2401 בטבלה.
      expect(ResponsaAuthorTable.bookIdOf(0x46109), 2401);
      // `בראשית`: 0x40300 בעץ, 3 בטבלה.
      expect(ResponsaAuthorTable.bookIdOf(0x40300), 3);
    });
  });

  group('decodeCp862', () {
    test('אותיות, סופיות, וסוגריים מתוקנים', () {
      final decoded = ResponsaAuthorTable.decodeCp862(
        record(1, 'ר\' ניסים גירונדי (הר"ן)').sublist(2),
      );
      expect(decoded, 'ר\' ניסים גירונדי (הר"ן)');
    });

    test('תו שאינו עברית או ASCII פוסל את הרשומה', () {
      expect(
        ResponsaAuthorTable.decodeCp862(Uint8List.fromList([0x80, 0xB0])),
        isNull,
      );
    });
  });

  group('parse', () {
    test('מחבר לחיבור שיש לו כותרת באותו מדור', () {
      final t = ResponsaAuthorTable.parse({
        'FILE25.RN2': table([record(2401, 'אבן האזל')]),
        'FILE65.RN2': table([record(2401, "ר' איסר זלמן מלצר")]),
      });
      expect(t.knows(2401), isTrue);
      expect(t.authorOf(2401), "ר' איסר זלמן מלצר");
    });

    test('רשומת מחבר בלי כותרת באותו מדור אינה נלקחת', () {
      // רשומה בלי כותרת במדור הייתה נותנת לספר מחבר שני.
      final t = ResponsaAuthorTable.parse({
        'FILE25.MA': table([record(2201, 'בית הבחירה')]),
        'FILE65.MA': table([record(2201, "ר' מנחם בן שלמה המאירי")]),
        'FILE65.RM': table([record(2201, "ר' משה בן מיימון")]),
      });
      expect(t.authorOf(2201), "ר' מנחם בן שלמה המאירי");
    });

    test('מפתח ביוגרפיה שאינו אדם אינו מחבר', () {
      final t = ResponsaAuthorTable.parse({
        'FILE25.MD': table([record(852, 'מדרש רבה בראשית')]),
        'FILE65.MD': table([record(852, 'מדרש רבה')]),
      });
      expect(t.knows(852), isTrue);
      expect(t.authorOf(852), isNull);
    });

    test('שני מחברים שונים לאותו חיבור — אין מחבר', () {
      final t = ResponsaAuthorTable.parse({
        'FILE25.A': table([record(7, 'X')]),
        'FILE65.A': table([record(7, "ר' ראשון")]),
        'FILE25.B': table([record(7, 'X')]),
        'FILE65.B': table([record(7, "ר' שני")]),
      });
      expect(t.knows(7), isTrue);
      expect(t.authorOf(7), isNull);
    });

    test('קובץ שגודלו אינו כפולה של רשומה מדולג כולו', () {
      final t = ResponsaAuthorTable.parse({
        'FILE25.A': table([record(1, 'X')]),
        'FILE65.A': Uint8List.fromList([
          ...record(1, "ר' מחבר"),
          0,
          0,
        ]),
      });
      expect(t.authorOf(1), isNull);
    });
  });

  group('parseDirectory', () {
    Uint8List directory(List<({String name, int offset, int size})> entries) {
      final bytes = BytesBuilder()
        ..add([entries.length & 0xFF, entries.length >> 8]);
      for (final e in entries) {
        final name = Uint8List(20)..setAll(0, e.name.codeUnits);
        final numbers = ByteData(8)
          ..setUint32(0, e.offset, Endian.little)
          ..setUint32(4, e.size, Endian.little);
        bytes
          ..add(name)
          ..add(numbers.buffer.asUint8List());
      }
      return bytes.toBytes();
    }

    test('שם, היסט וגודל', () {
      final parsed = ResponsaAuthorTable.parseDirectory(
        directory([(name: 'FILE65.RN2', offset: 100, size: 73)]),
        1000,
      );
      expect(parsed, [(name: 'FILE65.RN2', offset: 100, size: 73)]);
    });

    test('רשומה שחורגת מהקובץ — המבנה אינו מוכר', () {
      expect(
        ResponsaAuthorTable.parseDirectory(
          directory([(name: 'FILE65.RN2', offset: 990, size: 73)]),
          1000,
        ),
        isNull,
      );
    });
  });

  test('קריאה מארכיון על הדיסק — מהספרייה ועד הטבלה', () {
    final dir = Directory.systemTemp.createTempSync('responsa_authors');
    addTearDown(() => dir.deleteSync(recursive: true));
    final titles = table([record(2401, 'אבן האזל')]);
    final authors = table([record(2401, "ר' איסר זלמן מלצר")]);
    const headerSize = 2 + 2 * ResponsaAuthorTable.directoryEntrySize;
    final header = ByteData(headerSize)..setUint16(0, 2, Endian.little);
    final bytes = header.buffer.asUint8List();
    void entry(int index, String name, int offset, int size) {
      final at = 2 + index * ResponsaAuthorTable.directoryEntrySize;
      bytes.setAll(at, name.codeUnits);
      header
        ..setUint32(at + 20, offset, Endian.little)
        ..setUint32(at + 24, size, Endian.little);
    }

    entry(0, 'FILE25.RN2', headerSize, titles.length);
    entry(1, 'FILE65.RN2', headerSize + titles.length, authors.length);
    final archive = File(p.join(dir.path, 'FILE00'))
      ..writeAsBytesSync([...bytes, ...titles, ...authors]);

    final t = ResponsaAuthorTableReader.forArchive(archive.path);
    expect(t.authorOf(2401), "ר' איסר זלמן מלצר");
  });

  test('ארכיון שאינו במבנה המוכר — טבלה ריקה, לא חריג', () {
    final dir = Directory.systemTemp.createTempSync('responsa_authors');
    addTearDown(() => dir.deleteSync(recursive: true));
    final archive = File(p.join(dir.path, 'FILE00'))
      ..writeAsBytesSync(List.filled(64, 0xFF));
    expect(ResponsaAuthorTableReader.forArchive(archive.path).isEmpty, isTrue);
  });

  group('mayBeSamePerson', () {
    test('אותו אדם בכתיב אחר — ובלי התארים והמקום שבסוגריים', () {
      expect(
        ResponsaAuthorTable.mayBeSamePerson(
          'רבי חיים הלברשטאם (גליציה, המאה ה - 18)',
          "ר' חיים הלברשטם",
        ),
        isTrue,
      );
      expect(
        ResponsaAuthorTable.mayBeSamePerson(
          'רבי שלמה בן יצחק (צרפת, המאה ה - 11)',
          "ר' שלמה יצחקי",
        ),
        isTrue,
      );
    });

    test('שם האב ו"אבן" אינם שם משותף', () {
      expect(
        ResponsaAuthorTable.mayBeSamePerson(
          'רבי שלמה בן יצחק (צרפת, המאה ה - 11)',
          "ר' יצחק אלפסי",
        ),
        isFalse,
      );
      expect(
        ResponsaAuthorTable.mayBeSamePerson(
          'רבי יוסף אבן חביב',
          "ר' אברהם אבן עזרא",
        ),
        isFalse,
      );
    });

    test('שני אנשים שונים — גם כששניהם "הכהן"', () {
      expect(
        ResponsaAuthorTable.mayBeSamePerson(
          'רבי שלמה בן יצחק (צרפת, המאה ה - 11)',
          "ר' שמשון משנץ",
        ),
        isFalse,
      );
      expect(
        ResponsaAuthorTable.mayBeSamePerson(
          'רבי מסעוד הכהן (מרוקו, המאה ה - 19)',
          "ר' רחמים חי חיותה הכהן",
        ),
        isFalse,
      );
    });
  });

  group('authorOf — איזה מקור גובר', () {
    // מדף, חיבור (סוג 4, מזהה 2401 בסדר בתים הפוך), ויחידה שתחתיו.
    final book = ResponsaBookRow(
      chain: [
        (level: 0, param: 1 << 16, name: 'שו"ת'),
        (
          level: 1,
          param: (ResponsaStructure.workKind << 16) | 0x6109,
          name: 'אבן האזל',
        ),
        (level: 2, param: (6 << 16) | 0x0100, name: 'חלק א'),
      ],
    );
    const fromBibliography = ResponsaBibliographyEntry(
      title: 'אבן האזל',
      author: 'רבי אחר',
      edition: '',
      pubPlace: null,
      pubDate: null,
    );

    test('המזהה נלקח מצומת החיבור ולא מהיחידה', () {
      final authors = ResponsaAuthorTable.parse({
        'FILE25.RN2': table([record(2401, 'אבן האזל'), record(1, 'אחר')]),
        'FILE65.RN2': table([
          record(2401, "ר' איסר זלמן מלצר"),
          record(1, "ר' של היחידה"),
        ]),
      });
      expect(
        ResponsaCatalogWriter.authorOf(book, authors, fromBibliography),
        "ר' איסר זלמן מלצר",
      );
    });

    test('חיבור מוכר בלי מחבר — הביבליוגרפיה אינה ממלאת אותו', () {
      final authors = ResponsaAuthorTable.parse({
        'FILE25.RN2': table([record(2401, 'אבן האזל')]),
      });
      expect(
        ResponsaCatalogWriter.authorOf(book, authors, fromBibliography),
        isNull,
      );
    });

    test('רשומה שהמחבר בה אדם אחר נפסלת כולה — גם המקום והשנה', () {
      final authors = ResponsaAuthorTable.parse({
        'FILE25.RN2': table([record(2401, 'אבן האזל')]),
        'FILE65.RN2': table([record(2401, "ר' איסר זלמן מלצר")]),
      });
      const other = ResponsaBibliographyEntry(
        title: 'אבן האזל',
        author: 'רבי יעקב אחר (פולין, המאה ה - 19)',
        edition: 'ירושלים תשכ"ב',
        pubPlace: 'ירושלים',
        pubDate: 'תשכ"ב',
      );
      expect(
        ResponsaCatalogWriter.consistentRecord(book, authors, other),
        isNull,
      );

      const same = ResponsaBibliographyEntry(
        title: 'אבן האזל',
        author: 'רבי איסר זלמן מלצר (ליטא, ירושלים, המאה ה - 20)',
        edition: 'ירושלים תשכ"ב',
        pubPlace: 'ירושלים',
        pubDate: 'תשכ"ב',
      );
      expect(ResponsaCatalogWriter.consistentRecord(book, authors, same), same);
    });

    test('חיבור שהטבלה אינה מכירה — נסיגה לביבליוגרפיה', () {
      expect(
        ResponsaCatalogWriter.authorOf(
          book,
          ResponsaAuthorTable.empty,
          fromBibliography,
        ),
        'רבי אחר',
      );
    });
  });
}

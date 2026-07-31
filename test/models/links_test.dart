import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

Link _link({
  required String heRef,
  required int index2,
  String path2 = 'משנה ברורה',
  int index1 = 1,
  String connectionType = LinkTypes.commentary,
}) => Link(
  heRef: heRef,
  index1: index1,
  path2: path2,
  index2: index2,
  connectionType: connectionType,
);

/// קישורי משנ"ב בפורמט ה-heRef האמיתי שב-DB: `משנה ברורה,  <סימן>, <ס"ק>` —
/// מספר הס"ק הוא הרכיב האחרון, ו-index2 הוא סדר השורה בספר המפרש.
List<Link> _msbLinks(String siman, List<(String, int)> seifim) => [
  for (final (label, lineIndex) in seifim)
    _link(heRef: 'משנה ברורה,  $siman, $label', index2: lineIndex),
];

Future<List<String>> _orderedLabels(
  List<Link> links, {
  List<String> commentators = const ['משנה ברורה'],
  List<int> indexes = const [0],
  Set<String> typesToShow = const {},
}) async {
  final result = await getLinksforIndexs(
    indexes: indexes,
    links: links,
    commentatorsToShow: commentators,
    typesToShow: typesToShow,
  );
  return result.map((l) => l.heRef.split(',').last.trim()).toList();
}

void main() {
  test('getLinksforIndexs שומר קישורים נפרדים משורות מקור שונות', () async {
    final links = [
      _link(
        heRef: 'רש"י פסוק א',
        index1: 22,
        path2: 'רש"י על בראשית',
        index2: 5,
      ),
      _link(
        heRef: 'רש"י פסוק א',
        index1: 23,
        path2: 'רש"י על בראשית',
        index2: 5,
      ),
    ];

    final result = await getLinksforIndexs(
      indexes: const [21, 22],
      links: links,
      commentatorsToShow: const ['רש"י על בראשית'],
    );

    expect(result, hasLength(2));
    expect(result.first.path2, 'רש"י על בראשית');
    expect(result.first.index2, 5);
  });

  group('מיון בתוך אותו מפרש — ס"ק כרכיב האחרון ב-heRef', () {
    // המלכוד: מיון לפי heRef שובר את הסדר — טו/טז נכתבים באות ט' ולכן נופלים
    // לפני י' בהשוואת מחרוזות. המיון חייב להישאר לפי index2 (סדר השורות).
    test('ס"ק ט–יח בסדר מספרי, טו/טז אינם קופצים אחרי ט', () async {
      final links = _msbLinks('קנח', const [
        ('ט', 9),
        ('י', 10),
        ('יא', 11),
        ('יב', 12),
        ('יג', 13),
        ('יד', 14),
        ('טו', 15),
        ('טז', 16),
        ('יז', 17),
        ('יח', 18),
      ]);

      expect(await _orderedLabels(links), const [
        'ט',
        'י',
        'יא',
        'יב',
        'יג',
        'יד',
        'טו',
        'טז',
        'יז',
        'יח',
      ]);
    });

    test('או"ח שמ, ג — תשעת הס"ק בסדר שב-DB', () async {
      final links = _msbLinks('שמ', const [
        ('ט', 9632),
        ('י', 9633),
        ('יא', 9634),
        ('יב', 9635),
        ('יג', 9636),
        ('יד', 9637),
        ('טו', 9638),
        ('טז', 9639),
        ('יז', 9640),
      ]);

      expect(await _orderedLabels(links), const [
        'ט',
        'י',
        'יא',
        'יב',
        'יג',
        'יד',
        'טו',
        'טז',
        'יז',
      ]);
    });

    test('יד וטו בלבד — טו אחרי יד', () async {
      final links = _msbLinks('קיג', const [('טו', 15), ('יד', 14)]);
      expect(await _orderedLabels(links), const ['יד', 'טו']);
    });

    test('טז אחרי טו', () async {
      final links = _msbLinks('א', const [('טז', 16), ('טו', 15)]);
      expect(await _orderedLabels(links), const ['טו', 'טז']);
    });

    test('אחרי יד באים טו וטז, ורק אז יז', () async {
      final links = _msbLinks('רלב', const [
        ('יז', 17),
        ('טו', 15),
        ('יד', 14),
        ('טז', 16),
      ]);
      expect(await _orderedLabels(links), const ['יד', 'טו', 'טז', 'יז']);
    });

    test('הסדר אינו תלוי בסדר הקלט', () async {
      final ordered = _msbLinks('רנג', const [
        ('ח', 8),
        ('ט', 9),
        ('י', 10),
        ('יד', 14),
        ('טו', 15),
        ('טז', 16),
        ('יז', 17),
      ]);
      final shuffled = [
        ordered[5],
        ordered[1],
        ordered[6],
        ordered[0],
        ordered[4],
        ordered[3],
        ordered[2],
      ];

      expect(await _orderedLabels(shuffled), await _orderedLabels(ordered));
    });

    test('טווח רחב — עשרות ומאות ממוינים נכון', () async {
      final links = _msbLinks('רסא', const [
        ('ק', 100),
        ('נ', 50),
        ('כה', 25),
        ('ט', 9),
        ('טז', 16),
        ('כ', 20),
        ('ל', 30),
        ('טו', 15),
        ('מ', 40),
      ]);

      expect(await _orderedLabels(links), const [
        'ט',
        'טו',
        'טז',
        'כ',
        'כה',
        'ל',
        'מ',
        'נ',
        'ק',
      ]);
    });
  });

  group('מיון בתוך אותו מפרש — פורמטי heRef אחרים', () {
    test('טו/טז כרכיב אמצעי (סימן) ממוינים נכון', () async {
      final links = [
        _link(heRef: 'פרק טז, א', index2: 16),
        _link(heRef: 'פרק טו, א', index2: 15),
        _link(heRef: 'פרק יז, א', index2: 17),
        _link(heRef: 'פרק יד, א', index2: 14),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['משנה ברורה'],
      );

      expect(result.map((l) => l.index2).toList(), const [14, 15, 16, 17]);
    });

    test('heRef ריק בכל הקישורים — המיון עדיין לפי סדר השורות', () async {
      final links = [
        _link(heRef: '', index2: 7),
        _link(heRef: '', index2: 3),
        _link(heRef: '', index2: 11),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['משנה ברורה'],
      );

      expect(result.map((l) => l.index2).toList(), const [3, 7, 11]);
    });

    test('heRef שאינו גימטריה (כותרת ספר) אינו משבש את הסדר', () async {
      final links = [
        _link(heRef: 'משנה ברורה', index2: 20),
        _link(heRef: 'משנה ברורה', index2: 4),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['משנה ברורה'],
      );

      expect(result.map((l) => l.index2).toList(), const [4, 20]);
    });

    test('קישורים לסימנים שונים — לפי סדר השורות ולא לפי אות הסימן', () async {
      // מה-DB: סימן ריא (5314) לפני רטז (5427), אף שבהשוואת מחרוזות
      // "רטז" מקדים את "ריא" — הט' שבתוך המספר נופלת לפני הי'.
      final links = [
        _link(heRef: 'משנה ברורה,  רטז, מ', index2: 5427),
        _link(heRef: 'משנה ברורה,  ריא, כז', index2: 5314),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['משנה ברורה'],
      );

      expect(result.map((l) => l.index2).toList(), const [5314, 5427]);
    });

    test('סימן שמכיל טו/טז בתוך מספר גדול ממוין נכון', () async {
      final links = [
        _link(heRef: 'משנה ברורה,  שטז, א', index2: 316),
        _link(heRef: 'משנה ברורה,  קטו, א', index2: 115),
        _link(heRef: 'משנה ברורה,  רטו, א', index2: 215),
        _link(heRef: 'משנה ברורה,  קיא, א', index2: 111),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['משנה ברורה'],
      );

      expect(result.map((l) => l.index2).toList(), const [111, 115, 215, 316]);
    });

    test('חלקי ספר — ויקרא לפני במדבר, ולא לפי אות החומש', () async {
      // מה-DB: ויקרא (2707) לפני במדבר (3495), אף שבהשוואת מחרוזות ב' < ו'.
      final links = [
        _link(
          heRef: 'הכתב והקבלה, במדבר,  ה, יג, ג',
          index2: 3495,
          path2: 'הכתב והקבלה',
        ),
        _link(
          heRef: 'הכתב והקבלה, ויקרא,  ה, א, ב',
          index2: 2707,
          path2: 'הכתב והקבלה',
        ),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['הכתב והקבלה'],
      );

      expect(result.map((l) => l.index2).toList(), const [2707, 3495]);
    });

    test('שני קישורים לאותה שורת יעד נשמרים שניהם', () async {
      final links = [
        _link(heRef: 'משנה ברורה,  א, ה', index2: 5),
        _link(heRef: 'משנה ברורה,  א, ה', index2: 5, index1: 1),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['משנה ברורה'],
      );

      expect(result, hasLength(2));
      expect(result.every((l) => l.index2 == 5), isTrue);
    });
  });

  group('סדר המפרשים קודם למיון הפנימי', () {
    test('סדר commentatorsToShow קובע, גם כש-index2 הפוך', () async {
      final links = [
        _link(heRef: 'משנה ברורה,  א, א', index2: 1),
        _link(heRef: 'ביאור הלכה,  א, א', index2: 900, path2: 'ביאור הלכה'),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['ביאור הלכה', 'משנה ברורה'],
      );

      expect(result.map((l) => l.path2).toList(), const [
        'ביאור הלכה',
        'משנה ברורה',
      ]);
    });

    test('המיון הפנימי פועל בתוך כל מפרש בנפרד', () async {
      final links = [
        _link(heRef: 'משנה ברורה,  א, טו', index2: 15),
        _link(heRef: 'ביאור הלכה,  א, טז', index2: 16, path2: 'ביאור הלכה'),
        _link(heRef: 'משנה ברורה,  א, יד', index2: 14),
        _link(heRef: 'ביאור הלכה,  א, יד', index2: 14, path2: 'ביאור הלכה'),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['משנה ברורה', 'ביאור הלכה'],
      );

      expect(
        result.map((l) => '${l.path2}:${l.index2}').toList(),
        const [
          'משנה ברורה:14',
          'משנה ברורה:15',
          'ביאור הלכה:14',
          'ביאור הלכה:16',
        ],
      );
    });
  });

  group('סינון', () {
    test('קישור שאינו תלוי-טקסט נזרק', () async {
      final links = [
        _link(
          heRef: 'משנה ברורה,  א, א',
          index2: 1,
          connectionType: LinkTypes.reference,
        ),
        _link(heRef: 'משנה ברורה,  א, ב', index2: 2),
      ];

      expect(await _orderedLabels(links), const ['ב']);
    });

    test('index2 לא חוקי (0 ומטה) נזרק', () async {
      final links = [
        _link(heRef: 'משנה ברורה,  א, א', index2: 0),
        _link(heRef: 'משנה ברורה,  א, ב', index2: -3),
        _link(heRef: 'משנה ברורה,  א, ג', index2: 3),
      ];

      expect(await _orderedLabels(links), const ['ג']);
    });

    test('path2 ריק נזרק', () async {
      final links = [
        _link(heRef: 'משנה ברורה,  א, א', index2: 1, path2: ''),
        _link(heRef: 'משנה ברורה,  א, ב', index2: 2),
      ];

      expect(await _orderedLabels(links), const ['ב']);
    });

    test('מפרש שאינו ברשימת המפרשים נזרק', () async {
      final links = [
        _link(heRef: 'ט"ז,  א, א', index2: 1, path2: 'ט"ז'),
        _link(heRef: 'משנה ברורה,  א, ב', index2: 2),
      ];

      expect(await _orderedLabels(links), const ['ב']);
    });

    test('שורת מקור שאינה ברשימת האינדקסים נזרקת', () async {
      final links = [
        _link(heRef: 'משנה ברורה,  א, א', index2: 1, index1: 1),
        _link(heRef: 'משנה ברורה,  א, ב', index2: 2, index1: 9),
      ];

      expect(await _orderedLabels(links, indexes: const [0]), const ['א']);
    });

    test('typesToShow מסנן לפי סוג, והמיון נשמר', () async {
      final links = [
        _link(
          heRef: 'אונקלוס,  א, טז',
          index2: 16,
          path2: 'אונקלוס',
          connectionType: LinkTypes.targum,
        ),
        _link(
          heRef: 'אונקלוס,  א, יד',
          index2: 14,
          path2: 'אונקלוס',
          connectionType: LinkTypes.targum,
        ),
        _link(heRef: 'משנה ברורה,  א, א', index2: 1),
      ];

      expect(
        await _orderedLabels(
          links,
          commentators: const ['אונקלוס', 'משנה ברורה'],
          typesToShow: const {LinkTypes.targum},
        ),
        const ['יד', 'טז'],
      );
    });
  });

  group('קלט קצה', () {
    test('רשימת מפרשים ריקה מחזירה ריק', () async {
      final links = _msbLinks('א', const [('א', 1)]);
      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const [],
      );
      expect(result, isEmpty);
    });

    test('רשימת אינדקסים ריקה מחזירה ריק', () async {
      final links = _msbLinks('א', const [('א', 1)]);
      final result = await getLinksforIndexs(
        indexes: const [],
        links: links,
        commentatorsToShow: const ['משנה ברורה'],
      );
      expect(result, isEmpty);
    });

    test('רשימת קישורים ריקה מחזירה ריק', () async {
      final result = await getLinksforIndexs(
        indexes: const [0],
        links: const [],
        commentatorsToShow: const ['משנה ברורה'],
      );
      expect(result, isEmpty);
    });
  });
}

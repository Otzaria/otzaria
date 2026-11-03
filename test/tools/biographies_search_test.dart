import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';

Biography _bio(String name, {List<String> appelations = const []}) =>
    Biography(id: name, name: name, knownAs: appelations);

void main() {
  group('BiographiesRepository.filter', () {
    test('שאילתה ריקה מחזירה את כל הערכים כמות שהם', () {
      final entries = [_bio('רבי עקיבא'), _bio('אביי')];
      expect(BiographiesRepository.filter(entries, '   '), same(entries));
    });

    test('מתאים גם לפי כינוי', () {
      final entries = [
        _bio('רבי משה סופר', appelations: ['החתם סופר']),
      ];
      expect(
        BiographiesRepository.filter(entries, 'החתם סופר').single.name,
        'רבי משה סופר',
      );
    });

    test('מדויק < מתחיל ב- < מילה שלמה < מכיל', () {
      final entries = [
        _bio('שמעון רש״יא'),
        _bio('רבי רש״י הגדול'),
        _bio('רש״י הקדוש'),
        _bio('רש״י'),
      ];

      expect(
        BiographiesRepository.filter(entries, 'רש״י').map((b) => b.name),
        ['רש״י', 'רש״י הקדוש', 'רבי רש״י הגדול', 'שמעון רש״יא'],
      );
    });

    test('a name match ranks before an equal match on another name', () {
      final entries = [
        _bio('פלוני', appelations: ['רש״י']),
        _bio('רש״י'),
        _bio('אלמוני', appelations: ['רש״י הקדוש']),
        _bio('רש״י הקדוש'),
      ];

      expect(
        BiographiesRepository.filter(entries, 'רש״י').map((b) => b.name),
        ['רש״י', 'פלוני', 'רש״י הקדוש', 'אלמוני'],
      );
    });

    test('an exact other name ranks before a partial match on a name', () {
      final entries = [
        _bio('רבי משה בן מימון', appelations: ['הרמב"ם']),
        _bio('בנו של הרמב"ם הגדול'),
      ];

      expect(
        BiographiesRepository.filter(entries, 'הרמב"ם').first.name,
        'רבי משה בן מימון',
      );
    });

    test('Hebrew gershayim match ASCII quotes both ways', () {
      final ascii = [_bio('הרמב"ם')];
      final hebrew = [_bio('הרמב״ם')];

      expect(BiographiesRepository.filter(ascii, 'הרמב״ם'), ascii);
      expect(BiographiesRepository.filter(hebrew, 'הרמב"ם'), hebrew);
    });

    test('בדירוג שווה ממוין לפי שם', () {
      final entries = [_bio('אב יוסף'), _bio('אב דוד')];
      expect(BiographiesRepository.filter(entries, 'אב').map((b) => b.name), [
        'אב דוד',
        'אב יוסף',
      ]);
    });
  });

  group('filter (issue: דירוג חוזר מקמפל RegExp בכל השוואת מיון)', () {
    // בונה מאגר סינתטי גדול שמכסה את כל ענפי הדירוג (מדויק/מתחיל-ב/מילה
    // שלמה/מכיל/רק-בכינוי) ואת מקרה אי-ההתאמה, עם שם ייחודי לכל ערך כדי
    // שהמיון יהיה חד-משמעי (בלי קשרי שוויון בין מפתחות מיון זהים).
    List<Biography> buildLargeBiographySet(int count, String query) {
      final entries = <Biography>[];
      for (var i = 0; i < count; i++) {
        final suffix = i.toRadixString(36).padLeft(4, '0');
        String name;
        var appelations = const <String>[];
        switch (i % 5) {
          case 0:
            name = i == 0 ? query : '$query תלמיד $suffix';
          case 1:
            name = 'רבי $query $suffix הקדוש';
          case 2:
            name = 'מ$query$suffix';
          case 3:
            name = 'שמעון בן זכאי $suffix';
            appelations = ['$query הלבן $suffix'];
          default:
            name = 'יוסף הכהן $suffix';
        }
        entries.add(Biography(id: '$i', name: name, knownAs: appelations));
      }
      return entries;
    }

    // מימוש הלוגיקה הישנה: _matchRank מקמפל RegExp חדש בכל קריאה, וה-
    // השוואה במיון קוראת לו פעמיים לכל השוואה — O(n log n) קימפולים.
    int legacyMatchRank(String name, String query) {
      if (name == query) return 0;
      if (name.startsWith(query)) return 1;
      if (RegExp('(^|\\s)${RegExp.escape(query)}(\$|\\s)').hasMatch(name)) {
        return 2;
      }
      if (name.contains(query)) return 3;
      return 4;
    }

    // The rank of an entry over its name and other names, with the
    // RegExp compiled again in every call, as the naive version would.
    int legacyRank(Biography bio, String query) {
      var rank = legacyMatchRank(bio.name, query) * 2;
      for (final alias in bio.knownAs) {
        final aliasRank = legacyMatchRank(alias, query) * 2 + 1;
        if (aliasRank < rank) rank = aliasRank;
      }
      return rank;
    }

    List<Biography> filterLegacy(List<Biography> entries, String query) {
      return entries.where((bio) => legacyRank(bio, query) < 8).toList()
        ..sort((a, b) {
          final rankCompare = legacyRank(
            a,
            query,
          ).compareTo(legacyRank(b, query));
          if (rankCompare != 0) return rankCompare;
          return a.name.compareTo(b.name);
        });
    }

    test('הקטלוג החדש מכסה את כל ענפי הדירוג על מאגר קטן', () {
      const query = 'אברהם';
      final entries = buildLargeBiographySet(10, query);
      final result = BiographiesRepository.filter(entries, query);
      expect(result, isNotEmpty);
      expect(result.first.name, query);
    });

    test('תוצאת הסינון זהה בין המימוש הישן לחדש על מאגר גדול', () {
      const query = 'אברהם';
      final entries = buildLargeBiographySet(10000, query);

      final legacy = filterLegacy(entries, query);
      final current = BiographiesRepository.filter(entries, query);

      expect(
        current.map((b) => b.name).toList(),
        legacy.map((b) => b.name).toList(),
      );
      // מוודא שגם ערכים בלי שום התאמה (i % 5 == 4) אכן נופלים בחוץ.
      expect(current.length, lessThan(entries.length));
    });

    test('הקלדה הדרגתית על אותם ערכים זהה למימוש הישן בכל הקשה', () {
      final entries = buildLargeBiographySet(500, 'אברהם');
      // ההקשה הראשונה ('י') אינה בכינויים, כך שמה שנשמר בה חייב לשמש גם
      // את ההקשות הבאות, שמתאימות לכינויים.
      for (final typed in ['יוסף הכהן', 'אברהם', 'רבי אב', 'הלבן']) {
        for (var i = 1; i <= typed.length; i++) {
          final query = typed.substring(0, i);
          expect(
            BiographiesRepository.filter(entries, query).map((b) => b.name),
            filterLegacy(entries, query.trim()).map((b) => b.name),
            reason: query,
          );
        }
      }
    });

    test(
      'הסינון מהיר משמעותית כש-RegExp לא מקומפל מחדש בכל השוואה',
      () {
        const query = 'אברהם';
        final entries = buildLargeBiographySet(10000, query);

        final legacyStopwatch = Stopwatch()..start();
        filterLegacy(entries, query);
        legacyStopwatch.stop();

        final currentStopwatch = Stopwatch()..start();
        BiographiesRepository.filter(entries, query);
        currentStopwatch.stop();

        final legacyMicros = legacyStopwatch.elapsedMicroseconds;
        final currentMicros = currentStopwatch.elapsedMicroseconds;

        // סף שמרני (המדידה בפועל הראתה פי כ-15-20) כדי לא להיות תלוי-רעש ב-CI.
        expect(
          currentMicros * 3,
          lessThan(legacyMicros),
          reason: 'legacy=$legacyMicros µs, current=$currentMicros µs',
        );
      },
    );
  });
}

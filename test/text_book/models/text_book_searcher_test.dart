import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/models/text_book_searcher.dart';

/// מריץ חיפוש וממתין לסיומו (החיפוש רץ אסינכרונית ומודיע דרך listener).
Future<void> performSearch(TextBookSearcher searcher, String query) {
  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted) completer.complete();
  }

  searcher.addListener(listener);
  searcher.startTextSearch(query);
  return completer.future.whenComplete(() => searcher.removeListener(listener));
}

void main() {
  const bookData =
      '<h1>ספר בראשית</h1>\n'
      '<h2>פרק א</h2>\n'
      'בראשית ברא אלהים את השמים ואת הארץ\n'
      '<h2>פרק ב</h2>\n'
      'ויכלו השמים והארץ וכל צבאם\n'
      'ויברך אלהים את יום השביעי';

  group('startTextSearch', () {
    test('מוצא את כל השורות המכילות את הביטוי', () async {
      final searcher = TextBookSearcher(bookData);
      await performSearch(searcher, 'השמים');

      expect(searcher.searchResults, hasLength(2));
      expect(searcher.searchResults[0].index, 2);
      expect(searcher.searchResults[1].index, 4);
      expect(searcher.isSearching, isFalse);
      expect(searcher.searchProgress, 1.0);
    });

    test('הכתובת נבנית מהכותרות ומסננת את רמה 1 (שם הספר)', () async {
      final searcher = TextBookSearcher(bookData);
      await performSearch(searcher, 'השמים');

      expect(searcher.searchResults[0].address, isNot(contains('ספר בראשית')));
      expect(searcher.searchResults[0].address, contains('פרק א'));
    });

    test('כותרת חדשה באותה רמה מחליפה את הקודמת בכתובת', () async {
      final searcher = TextBookSearcher(bookData);
      await performSearch(searcher, 'השמים');

      final secondAddress = searcher.searchResults[1].address;
      expect(secondAddress, contains('פרק ב'));
      expect(secondAddress, isNot(contains('פרק א')));
    });

    test('הקטע (snippet) מכיל את הביטוי שחופש', () async {
      final searcher = TextBookSearcher(bookData);
      await performSearch(searcher, 'צבאם');

      expect(searcher.searchResults, hasLength(1));
      expect(searcher.searchResults.first.snippet, contains('צבאם'));
    });

    test('חיפוש בטקסט מנוקד מוצא ביטוי ללא ניקוד', () async {
      const nikudData = '<h2>פרק א</h2>\nבְּרֵאשִׁית בָּרָא אֱלֹהִים';
      final searcher = TextBookSearcher(nikudData);
      await performSearch(searcher, 'בראשית');

      expect(searcher.searchResults, hasLength(1));
      expect(searcher.searchResults.first.index, 1);
    });

    test('ביטוי שאינו קיים מחזיר רשימה ריקה', () async {
      final searcher = TextBookSearcher(bookData);
      await performSearch(searcher, 'אבגדהוז');

      expect(searcher.searchResults, isEmpty);
    });

    test('שאילתה ריקה מנקה תוצאות קודמות ומודיעה למאזינים', () async {
      final searcher = TextBookSearcher(bookData);
      await performSearch(searcher, 'השמים');
      expect(searcher.searchResults, isNotEmpty);

      var notified = false;
      searcher.addListener(() => notified = true);
      searcher.startTextSearch('');

      expect(searcher.searchResults, isEmpty);
      expect(searcher.isSearching, isFalse);
      expect(searcher.searchProgress, 0.0);
      expect(notified, isTrue);
    });

    test('searchSession גדל בכל חיפוש שמסתיים', () async {
      final searcher = TextBookSearcher(bookData);
      final initialSession = searcher.searchSession;

      await performSearch(searcher, 'השמים');
      expect(searcher.searchSession, initialSession + 1);

      await performSearch(searcher, 'צבאם');
      expect(searcher.searchSession, initialSession + 2);
    });
  });

  group('listeners', () {
    test('removeListener מפסיק לקבל עדכונים', () async {
      final searcher = TextBookSearcher(bookData);
      var count = 0;
      void listener() => count++;

      searcher.addListener(listener);
      await performSearch(searcher, 'השמים');
      expect(count, 1);

      searcher.removeListener(listener);
      await performSearch(searcher, 'צבאם');
      expect(count, 1);
    });
  });
}

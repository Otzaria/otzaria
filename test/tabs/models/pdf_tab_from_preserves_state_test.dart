import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/tab.dart';

import '../../helpers/memory_settings_cache.dart';

/// `OpenedTab.from` הוא מסלול השכפול של `CloneTab`, של מעבר שולחן עבודה,
/// של `CombinedTab` ושל `PdfCommentatorsTab`. הענף של [PdfBookTab] בו העביר
/// פרמטרי קונסטרוקטור בלבד, ולכן שלושת השדות שנקבעים **אחרי** הבנייה אבדו:
/// המפרשים הפעילים, התקריב ומצב הפריסה. אותם שדות שורדים
/// `toJson`/`fromJson` בלי בעיה, ולכן הפער היה בשכפול בלבד — וזו הסיבה
/// ש-`PdfCommentatorsTab.clone` העתיק אותם ידנית.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab source() {
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
      pageNumber: 7,
    );
    tab.activeCommentators = {'רש"י', 'רמב"ן'};
    tab.savedZoom = 1.75;
    tab.savedLayoutMode = PdfLayoutMode.regularView;
    return tab;
  }

  test(
    'OpenedTab.from משמר activeCommentators / savedZoom / savedLayoutMode',
    () {
      final tab = source();
      final copy = OpenedTab.from(tab) as PdfBookTab;

      expect(copy.activeCommentators, tab.activeCommentators);
      expect(copy.savedZoom, tab.savedZoom);
      expect(copy.savedLayoutMode, tab.savedLayoutMode);
    },
  );

  test('הסט מועתק ואינו משותף — שינוי בשכפול אינו נוגע במקור', () {
    final tab = source();
    final copy = OpenedTab.from(tab) as PdfBookTab;

    copy.activeCommentators.add('אבן עזרא');

    expect(tab.activeCommentators, hasLength(2));
  });

  test('clone() זהה ל-from', () {
    final tab = source();
    final copy = tab.clone() as PdfBookTab;

    expect(copy.activeCommentators, tab.activeCommentators);
    expect(copy.savedZoom, tab.savedZoom);
    expect(copy.savedLayoutMode, tab.savedLayoutMode);
  });

  test('toJson -> fromJson משמר (בקרה — עבר גם לפני התיקון)', () {
    final tab = source();
    final restored = PdfBookTab.fromJson(tab.toJson());

    expect(restored.activeCommentators, tab.activeCommentators);
    expect(restored.savedZoom, tab.savedZoom);
    expect(restored.savedLayoutMode, tab.savedLayoutMode);
  });

  group('externalMatches', () {
    PdfBookTab withMatches() {
      final tab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 1,
        externalMatches: ExternalBookMatches(
          pages: const [3, 8, 12],
          matchedTerms: const ['אברהם'],
          query: 'אברהם',
        ),
      );
      return tab;
    }

    test('OpenedTab.from משמר את עמודי ההתאמה', () {
      final tab = withMatches();
      final copy = OpenedTab.from(tab) as PdfBookTab;

      expect(copy.externalMatches.value?.pages, const [3, 8, 12]);
      expect(copy.externalMatches.value?.query, 'אברהם');
    });

    test('clone() משמר את עמודי ההתאמה', () {
      final tab = withMatches();
      final copy = tab.clone() as PdfBookTab;

      expect(copy.externalMatches.value?.pages, const [3, 8, 12]);
    });

    test('toJson -> fromJson משמר (בקרה)', () {
      final tab = withMatches();
      final restored = PdfBookTab.fromJson(tab.toJson());

      expect(restored.externalMatches.value?.pages, const [3, 8, 12]);
    });
  });
}

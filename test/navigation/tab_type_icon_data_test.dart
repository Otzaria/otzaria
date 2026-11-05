import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

import '../helpers/memory_settings_cache.dart';

/// [tabTypeIconData] הוא הגליף שמצויר במוק הגרירה של כרטיסיה שאין מה
/// לצלם בה, ולכן קריסה של המיפוי — כל הכרטיסיות מקבלות אותו אייקון —
/// אינה נראית בשום מקום אחר.
///
/// ⚠️ מה שהבדיקה הזו **אינה** מכסה: שהגליף עצמו מרונדר. `flutter_test`
/// אינו טוען גופני אייקונים, ולכן "ריבוע ריק במקום אייקון" נבדק רק
/// ידנית באפליקציה.
void main() {
  // `PdfBookTab` קורא ל-`Settings.getValue` בבנייה.
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  PdfBookTab pdfTab() => PdfBookTab(
    book: PdfBook(title: 'ספר', path: 'a.pdf'),
    pageNumber: 1,
  );

  TextBookTab textTab([String title = 'בראשית']) =>
      TextBookTab(book: TextBook(title: title, categoryId: 1), index: 0);

  test('כל סוג כרטיסיה מקבל את האייקון שלו', () {
    // אייקון PDF של אוצריא, כמו ברצועה העליונה (q10 Q14 C).
    expect(tabTypeIconData(pdfTab()), OtzariaIcons.document_pdf_24_regular);
    expect(
      tabTypeIconData(SearchingTab('חיפוש', null)),
      OtzariaIcons.search_24_regular,
    );
    expect(
      tabTypeIconData(
        CombinedTab(rightTab: textTab(), leftTab: textTab('שמות')),
      ),
      FluentIcons.split_horizontal_24_regular,
    );
    expect(
      tabTypeIconData(ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה')),
      FluentIcons.toolbox_24_regular,
    );
    // ⚠️ כרטיסיית טקסט היא היחידה ש-`buildTabTypeIcon` מחזיר לה `null`,
    // וכאן היא **חייבת** לקבל אייקון: מוק בלי אייקון הוא מלבן ריק עם
    // כותרת תלויה באוויר.
    expect(tabTypeIconData(textTab()), FluentIcons.document_24_regular);
  });

  test('סוגי כרטיסיה שונים אינם מקבלים אותו אייקון', () {
    final icons = <OpenedTab>[
      pdfTab(),
      textTab(),
      SearchingTab('חיפוש', null),
      ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה'),
    ].map(tabTypeIconData).toSet();

    expect(icons, hasLength(4));
  });

  /// כרטיסיית טקסט של מסמך שיובא: הפורמט נקבע לפי הסיומת, כמו ברשימות.
  TextBookTab documentTab(String fileType, {bool isUserBook = true}) =>
      TextBookTab(
        book: TextBook(
          title: 'מסמך',
          categoryId: 1,
          filePath: 'C:/docs/a.$fileType',
          fileType: fileType,
          source: BookSource.fromUserFlag(isUserBook),
        ),
        index: 0,
      );

  test('מסמכי Word, HTML ו-Markdown מקבלים אייקון משלהם בראש הכרטיסיה', () {
    for (final type in ['docx', 'docm', 'doc']) {
      expect(
        tabContentIconData(documentTab(type)),
        OtzariaIcons.document_word_24_regular,
        reason: type,
      );
    }
    for (final type in ['html', 'htm']) {
      expect(
        tabContentIconData(documentTab(type)),
        OtzariaIcons.document_html_24_regular,
        reason: type,
      );
    }
    for (final type in ['md', 'markdown']) {
      expect(
        tabContentIconData(documentTab(type)),
        OtzariaIcons.document_md_24_regular,
        reason: type,
      );
    }
    expect(
      tabTypeIconData(documentTab('docx')),
      OtzariaIcons.document_word_24_regular,
    );
  });

  test('כרטיסיות אחרות נשארות בלי אייקון תוכן', () {
    expect(tabContentIconData(textTab()), isNull);
    expect(tabContentIconData(documentTab('txt')), isNull);
    expect(tabContentIconData(documentTab('epub')), isNull);
    expect(tabContentIconData(pdfTab()), isNull);
    expect(
      tabContentIconData(ToolTab(toolId: 'builtin.calendar', title: 'לוח')),
      isNull,
    );
    expect(
      tabContentIconData(SearchingTab('חיפוש', null)),
      OtzariaIcons.search_24_regular,
    );
  });

  test('כל כרטיסיית חיפוש, גם סמנטית, מקבלת את אייקון החיפוש הרגיל', () {
    final semantic = SemanticSearchTab(
      options: const SemanticQueryOptions(query: 'קקק'),
    );
    addTearDown(semantic.dispose);
    expect(
      tabContentIconData(semantic),
      OtzariaIcons.search_24_regular,
    );
  });

  test('אייקון החיפוש מחליף את המילה "חיפוש:" בכותרת ולא מתווסף אליה', () {
    final tab = SearchingTab('x', null);
    expect(tabTitleBesideContentIcon(tab, 'חיפוש: קקק'), 'קקק');
    // בלי שאילתה המילה נשארת: כרטיסיה בלי טקסט אינה ניתנת לזיהוי.
    expect(tabTitleBesideContentIcon(tab, 'חיפוש'), 'חיפוש');
    // כרטיסיה בלי אייקון תוכן לא משתנה.
    expect(tabTitleBesideContentIcon(textTab(), 'חיפוש: קקק'), 'חיפוש: קקק');
    expect(tabTitleBesideContentIcon(pdfTab(), 'חיפוש: קקק'), 'חיפוש: קקק');
  });
}

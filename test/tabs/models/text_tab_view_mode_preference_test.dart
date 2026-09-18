// issue #1424: ספר שהמשתמש קורא בצורת הדף נפתח מההיסטוריה (ומהסימניות) בתצוגה
// רגילה. ההעדפה נשמרת פר-ספר בהחלפת התצוגה, אבל רק מסלול הפתיחה מהספרייה
// (BookOpenCoordinator) ותוצאות החיפוש זכרו לקרוא אותה — ההיסטוריה והסימניות
// בנו את הטאב דרך OpenedTab.fromBook בלי לציין מצב, והטאב נפל ל-false.
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../helpers/memory_settings_cache.dart';

bool _initialPageShape(OpenedTab tab) =>
    ((tab as TextBookTab).bloc.state as TextBookInitial).showPageShapeView;

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('פתיחת ספר מכבדת את העדפת צורת הדף שנשמרה לו (issue #1424)', () {
    test('ספר שנשמר לו "צורת הדף" נפתח כך גם בלי שהקורא ציין מצב', () async {
      await PageShapeSettingsManager.saveViewModePreference('עירובין', true);

      // כך נבנה הטאב במסך ההיסטוריה ובמסך הסימניות.
      final tab = OpenedTab.fromBook(TextBook(title: 'עירובין'), 3);

      expect(_initialPageShape(tab), isTrue);
      tab.dispose();
    });

    test('ספר בלי העדפה שמורה נפתח בתצוגה רגילה', () {
      final tab = OpenedTab.fromBook(TextBook(title: 'בראשית'), 0);
      expect(_initialPageShape(tab), isFalse);
      tab.dispose();
    });

    test('העדפה שמורה "תצוגה רגילה" מכבדת גם היא', () async {
      await PageShapeSettingsManager.saveViewModePreference('עירובין', false);
      final tab = OpenedTab.fromBook(TextBook(title: 'עירובין'), 3);
      expect(_initialPageShape(tab), isFalse);
      tab.dispose();
    });

    test('ערך מפורש מהקורא (שחזור טאב שמור) גובר על ההעדפה', () async {
      await PageShapeSettingsManager.saveViewModePreference('עירובין', true);
      final tab = TextBookTab(
        book: TextBook(title: 'עירובין'),
        index: 3,
        showPageShapeView: false,
      );
      expect(_initialPageShape(tab), isFalse);
      tab.dispose();
    });
  });
}

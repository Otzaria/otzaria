import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TabsRepository repository;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tabs_repository_test');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('tabs');
    repository = TabsRepository();
  });

  tearDown(() async {
    await Hive.box('tabs').clear();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TabsRepository', () {
    test('saveTabs/loadTabs משחזרים CommentatorsTab', () async {
      final sourceTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 4,
      );
      addTearDown(sourceTab.dispose);

      final commentatorsTab = CommentatorsTab(sourceTab: sourceTab);
      addTearDown(commentatorsTab.dispose);

      await repository.saveTabs([commentatorsTab], 0);

      final loaded = repository.loadTabs();
      addTearDown(() {
        for (final tab in loaded) {
          tab.dispose();
        }
      });

      expect(loaded, hasLength(1));
      expect(loaded.single, isA<CommentatorsTab>());
      expect(
        (loaded.single as CommentatorsTab).sourceTab.book.title,
        'ספר בדיקה',
      );
    });

    test('PdfCommentatorsTab נשמר ומשוחזר', () async {
      final pdfSource = PdfBookTab(
        book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
        pageNumber: 2,
      );
      addTearDown(pdfSource.dispose);

      final pdfCommentatorsTab = PdfCommentatorsTab(sourceTab: pdfSource);
      await repository.saveTabs([pdfCommentatorsTab], 0);

      final loaded = repository.loadTabs();
      addTearDown(() {
        for (final tab in loaded) {
          tab.dispose();
        }
      });

      expect(loaded, hasLength(1));
      expect(loaded.single, isA<PdfCommentatorsTab>());
      final restored = loaded.single as PdfCommentatorsTab;
      expect(restored.sourceTab.book.title, 'PDF בדיקה');
      expect(restored.sourceTab.pageNumber, 2);
      expect(repository.loadCurrentTabIndex(), 0);
    });

    test(
      'CombinedTab עם PdfCommentatorsTab נשמר ומשוחזר (side-by-side)',
      () async {
        final pdfSource = PdfBookTab(
          book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
          pageNumber: 2,
        );
        final textTab = TextBookTab(
          book: TextBook(title: 'ספר בדיקה'),
          index: 1,
        );
        addTearDown(pdfSource.dispose);
        addTearDown(textTab.dispose);

        final combined = CombinedTab(
          rightTab: PdfCommentatorsTab(sourceTab: pdfSource),
          leftTab: textTab,
        );
        await repository.saveTabs([combined], 0);

        final loaded = repository.loadTabs();
        addTearDown(() {
          for (final tab in loaded) {
            tab.dispose();
          }
        });

        expect(loaded, hasLength(1));
        expect(loaded.single, isA<CombinedTab>());
        final restored = loaded.single as CombinedTab;
        expect(restored.rightTab, isA<PdfCommentatorsTab>());
        expect(restored.leftTab, isA<TextBookTab>());
      },
    );

    test('loadCurrentTabIndex משחזר את האינדקס שנשמר', () async {
      final firstTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 1,
      );
      final secondTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה 2'),
        index: 2,
      );
      final thirdTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה 3'),
        index: 3,
      );
      final fourthTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה 4'),
        index: 4,
      );
      addTearDown(firstTab.dispose);
      addTearDown(secondTab.dispose);
      addTearDown(thirdTab.dispose);
      addTearDown(fourthTab.dispose);

      await repository.saveTabs([firstTab, secondTab, thirdTab, fourthTab], 3);

      expect(repository.loadCurrentTabIndex(), 3);
    });

    test(
      'טאבים מעורבים (טקסט + מפרשי PDF) — כולם נשמרים והאינדקס נשמר',
      () async {
        final textTab = TextBookTab(
          book: TextBook(title: 'ספר בדיקה'),
          index: 1,
        );
        final pdfSource = PdfBookTab(
          book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
          pageNumber: 2,
        );
        addTearDown(textTab.dispose);
        addTearDown(pdfSource.dispose);

        final pdfCommentatorsTab = PdfCommentatorsTab(sourceTab: pdfSource);
        await repository.saveTabs([textTab, pdfCommentatorsTab], 1);

        final loaded = repository.loadTabs();
        addTearDown(() {
          for (final tab in loaded) {
            tab.dispose();
          }
        });

        expect(loaded, hasLength(2));
        expect(loaded[0], isA<TextBookTab>());
        expect(loaded[1], isA<PdfCommentatorsTab>());
        expect(repository.loadCurrentTabIndex(), 1);
      },
    );

    test(
      'saveCurrentTabIndex מעדכן את האינדקס בלי לדרוס את הטאבים השמורים',
      () async {
        final firstTab = TextBookTab(
          book: TextBook(title: 'ספר בדיקה'),
          index: 1,
        );
        final secondTab = TextBookTab(
          book: TextBook(title: 'ספר בדיקה 2'),
          index: 2,
        );
        addTearDown(firstTab.dispose);
        addTearDown(secondTab.dispose);

        await repository.saveTabs([firstTab, secondTab], 0);
        await repository.saveCurrentTabIndex([firstTab, secondTab], 1);

        // האינדקס התעדכן...
        expect(repository.loadCurrentTabIndex(), 1);

        // ...והטאבים נשארו כפי שהיו (לא קודדו מחדש/נדרסו)
        final loaded = repository.loadTabs();
        addTearDown(() {
          for (final tab in loaded) {
            tab.dispose();
          }
        });
        expect(loaded, hasLength(2));
      },
    );

    test('remapBookPaths ממפה נתיב PDF מתיקייה ישנה לחדשה', () async {
      final oldDir = p.join('/lib', 'old');
      final newDir = p.join('/lib', 'new');
      final pdf = PdfBookTab(
        book: PdfBook(
          title: 'מסכת ברכות',
          path: p.join(oldDir, 'תלמוד בבלי', 'ברכות.pdf'),
        ),
        pageNumber: 1,
      );
      addTearDown(pdf.dispose);
      await repository.saveTabs([pdf], 0);

      await repository.remapBookPaths(oldDir, newDir);

      final loaded = repository.loadTabs();
      addTearDown(() {
        for (final tab in loaded) {
          tab.dispose();
        }
      });
      final restored = loaded.single as PdfBookTab;
      expect(restored.book.path, p.join(newDir, 'תלמוד בבלי', 'ברכות.pdf'));
    });

    test('remapBookPaths לא נוגע בנתיבים שמחוץ לתיקייה הישנה', () async {
      final pdf = PdfBookTab(
        book: PdfBook(title: 'אחר', path: p.join('/other', 'book.pdf')),
        pageNumber: 1,
      );
      addTearDown(pdf.dispose);
      await repository.saveTabs([pdf], 0);

      await repository.remapBookPaths(
        p.join('/lib', 'old'),
        p.join('/lib', 'new'),
      );

      final loaded = repository.loadTabs();
      addTearDown(() {
        for (final tab in loaded) {
          tab.dispose();
        }
      });
      expect(
        (loaded.single as PdfBookTab).book.path,
        p.join('/other', 'book.pdf'),
      );
    });

    test('remapTabsInMemory ממפה נתיב PDF בזיכרון ומחזיר טאב חדש', () {
      final oldDir = p.join('/lib', 'old');
      final newDir = p.join('/lib', 'new');
      final pdf = PdfBookTab(
        book: PdfBook(
          title: 'מסכת ברכות',
          path: p.join(oldDir, 'תלמוד בבלי', 'ברכות.pdf'),
        ),
        pageNumber: 3,
      );
      addTearDown(pdf.dispose);

      final remapped = repository.remapTabsInMemory([pdf], oldDir, newDir);
      addTearDown(() {
        for (final tab in remapped) {
          tab.dispose();
        }
      });

      expect(remapped, hasLength(1));
      final restored = remapped.single as PdfBookTab;
      expect(restored.book.path, p.join(newDir, 'תלמוד בבלי', 'ברכות.pdf'));
      expect(restored.pageNumber, 3);
      expect(identical(restored, pdf), isFalse, reason: 'טאב ששונה נבנה מחדש');
    });

    test('remapTabsInMemory משמר אובייקט מקורי לטאב שלא השתנה', () {
      final outside = PdfBookTab(
        book: PdfBook(title: 'אחר', path: p.join('/other', 'book.pdf')),
        pageNumber: 1,
      );
      final textTab = TextBookTab(book: TextBook(title: 'ספר'), index: 1);
      addTearDown(outside.dispose);
      addTearDown(textTab.dispose);

      final remapped = repository.remapTabsInMemory(
        [outside, textTab],
        p.join('/lib', 'old'),
        p.join('/lib', 'new'),
      );

      expect(
        identical(remapped[0], outside),
        isTrue,
        reason: 'נתיב מחוץ לתיקייה — אותו אובייקט',
      );
      expect(
        identical(remapped[1], textTab),
        isTrue,
        reason: 'טאב טקסט ללא נתיב — אותו אובייקט',
      );
    });

    test('saveCurrentTabIndex שומר את האינדקס כשכל הטאבים נשמרים', () async {
      final firstTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 1,
      );
      final pdfSource = PdfBookTab(
        book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
        pageNumber: 2,
      );
      final thirdTab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה 3'),
        index: 3,
      );
      addTearDown(firstTab.dispose);
      addTearDown(pdfSource.dispose);
      addTearDown(thirdTab.dispose);

      final pdfCommentatorsTab = PdfCommentatorsTab(sourceTab: pdfSource);
      addTearDown(pdfCommentatorsTab.dispose);
      final tabs = [firstTab, pdfCommentatorsTab, thirdTab];

      // כל הטאבים נשמרים, כולל PdfCommentatorsTab — לכן האינדקס נשמר כמות שהוא.
      await repository.saveCurrentTabIndex(tabs, 2);

      expect(repository.loadCurrentTabIndex(), 2);
    });
  });
}

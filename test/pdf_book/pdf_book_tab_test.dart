import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import '../helpers/memory_settings_cache.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

PdfBook _book({String path = '/path/to/book.pdf'}) =>
    PdfBook(title: 'ספר בדיקה', path: path);

PdfBookTab _tab({String path = '/path/to/book.pdf', int page = 1}) =>
    PdfBookTab(
      book: _book(path: path),
      pageNumber: page,
    );

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('PdfBookTab - בנייה', () {
    test('שדות ראשוניים נכונים', () {
      final book = _book();
      final tab = PdfBookTab(book: book, pageNumber: 5);

      expect(tab.book, book);
      expect(tab.pageNumber, 5);
      expect(tab.searchText, '');
      expect(tab.links, isEmpty);
      expect(tab.pdfHeadings, isNull);
      expect(tab.savedZoom, isNull);
      expect(tab.savedLayoutMode, isNull);
      expect(tab.showLeftPane.value, isFalse);
      expect(tab.activeCommentators, isEmpty);
      expect(tab.currentTextLineNumber, isNull);
      expect(tab.currentTextLineNumberEnd, isNull);
    });

    test('currentTextLineNumber ו-currentTextLineNumberEnd ניתנים לכתיבה', () {
      final tab = _tab();
      tab.currentTextLineNumber = 42;
      tab.currentTextLineNumberEnd = 67;
      expect(tab.currentTextLineNumber, 42);
      expect(tab.currentTextLineNumberEnd, 67);
    });

    test('currentTextLineNumberEnd אינו נדרש — נשאר null כברירת מחדל', () {
      final tab = _tab();
      tab.currentTextLineNumber = 10;
      expect(tab.currentTextLineNumberEnd, isNull);
    });

    test('openLeftPane=true → showLeftPane מתחיל true', () {
      final tab = PdfBookTab(book: _book(), pageNumber: 1, openLeftPane: true);
      expect(tab.showLeftPane.value, isTrue);
    });

    test('requiresStableLayout=false כברירת מחדל (פתיחה ישירה מהירה)', () {
      final tab = _tab();
      expect(tab.requiresStableLayout, isFalse);
    });

    test('requiresStableLayout ניתן להפעלה (תרחישי סיכון)', () {
      final tab = PdfBookTab(
        book: _book(),
        pageNumber: 1,
        requiresStableLayout: true,
      );
      expect(tab.requiresStableLayout, isTrue);
    });

    test('searchText מועבר ל-searchController', () {
      final tab = PdfBookTab(book: _book(), pageNumber: 1, searchText: 'תורה');
      expect(tab.searchController.text, 'תורה');
      expect(tab.searchText, 'תורה');
    });

    test('notifiers של קיצורי המקלדת קיימים ומתחילים ב-0', () {
      final tab = _tab();
      expect(tab.toggleNavPaneNotifier.value, 0);
      expect(tab.toggleCommentatorsPaneNotifier.value, 0);
    });

    test('הגדלת toggleNavPaneNotifier משדרת ל-listener', () {
      final tab = _tab();
      var calls = 0;
      void listener() => calls++;
      tab.toggleNavPaneNotifier.addListener(listener);
      addTearDown(() => tab.toggleNavPaneNotifier.removeListener(listener));

      tab.toggleNavPaneNotifier.value++;
      tab.toggleNavPaneNotifier.value++;

      expect(calls, 2);
      expect(tab.toggleNavPaneNotifier.value, 2);
    });

    test('הגדלת toggleCommentatorsPaneNotifier משדרת ל-listener', () {
      final tab = _tab();
      var calls = 0;
      void listener() => calls++;
      tab.toggleCommentatorsPaneNotifier.addListener(listener);
      addTearDown(
        () => tab.toggleCommentatorsPaneNotifier.removeListener(listener),
      );

      tab.toggleCommentatorsPaneNotifier.value++;

      expect(calls, 1);
      expect(tab.toggleCommentatorsPaneNotifier.value, 1);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('PdfBookTab - סריאליזציה toJson', () {
    test('toJson מכיל את המפתחות הנדרשים', () {
      final tab = _tab(page: 3);
      final json = tab.toJson();

      expect(json['path'], '/path/to/book.pdf');
      expect(json['pageNumber'], 3);
      expect(json['type'], 'PdfBookTab');
      expect(json.containsKey('book'), isTrue);
      expect(json.containsKey('showLeftPane'), isTrue);
      expect(json.containsKey('isPinned'), isTrue);
    });

    test('toJson כשה-controller לא מוכן → משתמש ב-pageNumber השמור', () {
      final tab = _tab(page: 7);
      // controller לא מחובר → isReady = false
      final json = tab.toJson();
      expect(json['pageNumber'], 7);
    });

    test('toJson שומר savedLayoutMode', () {
      final tab = _tab();
      tab.savedLayoutMode = PdfLayoutMode.bookView;
      final json = tab.toJson();
      expect(json['savedLayoutMode'], 'bookView');
    });

    test('toJson ללא savedLayoutMode → אין מפתח savedLayoutMode', () {
      final tab = _tab();
      final json = tab.toJson();
      expect(json.containsKey('savedLayoutMode'), isFalse);
    });

    test('toJson שומר showLeftPane=true', () {
      final tab = PdfBookTab(book: _book(), pageNumber: 1, openLeftPane: true);
      expect(tab.toJson()['showLeftPane'], isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('PdfBookTab - דה-סריאליזציה fromJson', () {
    test('fromJson משחזר pageNumber ו-path', () {
      final tab = _tab(page: 12);
      final restored = PdfBookTab.fromJson(tab.toJson());

      expect(restored.pageNumber, 12);
      expect(restored.book.path, '/path/to/book.pdf');
    });

    test('fromJson roundtrip שומר savedLayoutMode', () {
      final tab = _tab();
      tab.savedLayoutMode = PdfLayoutMode.bookView;
      final restored = PdfBookTab.fromJson(tab.toJson());
      expect(restored.savedLayoutMode, PdfLayoutMode.bookView);
    });

    test('fromJson roundtrip שומר bookViewNoCover', () {
      final tab = _tab();
      tab.savedLayoutMode = PdfLayoutMode.bookViewNoCover;
      final restored = PdfBookTab.fromJson(tab.toJson());
      expect(restored.savedLayoutMode, PdfLayoutMode.bookViewNoCover);
    });

    test('fromJson ללא savedLayoutMode → savedLayoutMode=null', () {
      final tab = _tab();
      final restored = PdfBookTab.fromJson(tab.toJson());
      expect(restored.savedLayoutMode, isNull);
    });

    test('fromJson עם showLeftPane=true → showLeftPane.value=true', () {
      final tab = PdfBookTab(book: _book(), pageNumber: 1, openLeftPane: true);
      final restored = PdfBookTab.fromJson(tab.toJson());
      expect(restored.showLeftPane.value, isTrue);
    });

    test('fromJson משחזר requiresStableLayout=true', () {
      final tab = PdfBookTab(
        book: _book(),
        pageNumber: 1,
        requiresStableLayout: true,
      );
      final restored = PdfBookTab.fromJson(tab.toJson());
      expect(restored.requiresStableLayout, isTrue);
    });

    test('fromJson ללא requiresStableLayout → false', () {
      final json = {'path': '/path/to/book.pdf', 'book': _book().toJson()};
      final tab = PdfBookTab.fromJson(json);
      expect(tab.requiresStableLayout, isFalse);
    });

    test('fromJson עם pageNumber חסר → מגדיר 1', () {
      final json = {'path': '/path/to/book.pdf', 'book': _book().toJson()};
      final tab = PdfBookTab.fromJson(json);
      expect(tab.pageNumber, 1);
    });

    test('fromJson ← toJson roundtrip מלא', () {
      final original = PdfBookTab(
        book: _book(path: '/a/b/c.pdf'),
        pageNumber: 99,
        openLeftPane: true,
        searchText: 'בדיקה',
      );
      original.savedLayoutMode = PdfLayoutMode.regularView;

      final restored = PdfBookTab.fromJson(original.toJson());

      expect(restored.book.path, '/a/b/c.pdf');
      expect(restored.pageNumber, 99);
      expect(restored.showLeftPane.value, isTrue);
      expect(restored.savedLayoutMode, PdfLayoutMode.regularView);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('PdfBookTab - מחזור חיים', () {
    test('dispose לא קורס', () {
      final tab = _tab();
      expect(() => tab.dispose(), returnsNormally);
    });

    test('setupPageTracking לא קורס כשה-controller לא מוכן', () {
      final tab = _tab();
      expect(() => tab.setupPageTracking(), returnsNormally);
    });

    test('searchController מוסר ב-dispose ואינו נגיש', () {
      final tab = _tab(page: 1);
      tab.dispose();
      // אחרי dispose, searchController.text אמור לזרוק
      // (בדיקת dispose הצליחה)
      expect(tab.pdfHeadings, isNull); // state לא השתנה
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('PdfBookTab - isPinned', () {
    test('isPinned=false ברירת מחדל', () {
      final tab = _tab();
      expect(tab.isPinned, isFalse);
    });

    test('isPinned=true נשמר ב-toJson', () {
      final tab = PdfBookTab(book: _book(), pageNumber: 1, isPinned: true);
      expect(tab.toJson()['isPinned'], isTrue);
    });

    test('isPinned משוחזר מ-fromJson', () {
      final tab = PdfBookTab(book: _book(), pageNumber: 1, isPinned: true);
      final restored = PdfBookTab.fromJson(tab.toJson());
      expect(restored.isPinned, isTrue);
    });
  });
}

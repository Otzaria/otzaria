import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import '../../helpers/memory_settings_cache.dart';

// מוודא ש-requiresStableLayout מושבת בפתיחה רגילה (progressive loading פעיל,
// פתיחה מהירה) ומופעל בתרחישי סיכון (דף יומי / מעבר טקסט->PDF) כפי שנקבע
// בקומיט 137e7c6b6.
void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  final book = PdfBook(title: 'ספר לדוגמה', path: '/tmp/book.pdf');

  test('פתיחת PDF רגילה לא מפעילה requiresStableLayout', () {
    final tab = OpenedTab.fromBook(book, 1) as PdfBookTab;
    expect(tab.requiresStableLayout, isFalse);
  });

  test('דף יומי / מעבר טקסט->PDF מפעילים requiresStableLayout', () {
    final tab = OpenedTab.fromBook(book, 1, requiresStableLayout: true)
        as PdfBookTab;
    expect(tab.requiresStableLayout, isTrue);
  });

  test('שכפול טאב (OpenedTab.from) שומר את requiresStableLayout', () {
    final riskyTab = PdfBookTab(
      book: book,
      pageNumber: 1,
      requiresStableLayout: true,
    );

    final cloned = OpenedTab.from(riskyTab) as PdfBookTab;
    expect(cloned.requiresStableLayout, isTrue);
  });

  test('toJson/fromJson שומר את requiresStableLayout', () {
    final tab = PdfBookTab(
      book: book,
      pageNumber: 1,
      requiresStableLayout: true,
    );

    final restored = PdfBookTab.fromJson(tab.toJson());
    expect(restored.requiresStableLayout, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_library_tree.dart';
import 'package:otzaria/models/books.dart';

/// התיקיות הווירטואליות שמציגות ספרי בר אילן בתוך קטגוריות אוצריא.
void main() {
  ExternalLibraryBook book(String title, String categoryPath, int id) =>
      ExternalLibraryBook(
        title: title,
        id: id,
        link: null,
        heCategories: categoryPath,
        externalLibraryId: 'rp:$id',
      );

  test('ספר שו"ת נכנס לתיקייה בתוך שו״ת', () {
    final tree = ResponsaLibraryTree.build([
      book(
        'תורת יקותיאל אישות',
        'ספרי שאלות ותשובות (שו"ת) > ספרי שאלות ותשובות - אחרונים',
        1,
      ),
    ]);
    final folder = tree.folderFor('/שו״ת');
    expect(folder, isNotNull);
    expect(folder!.title, ResponsaLibraryTree.folderTitle);
    // הרמה השנייה של בר אילן נשמרת כתיקייה בפנים.
    expect(folder.subCategories.single.title, 'ספרי שאלות ותשובות - אחרונים');
    expect(
      folder.subCategories.single.books.single.title,
      'תורת יקותיאל אישות',
    );
  });

  test('רמה שנצרכה בשיוך אינה חוזרת כתיקייה', () {
    final tree = ResponsaLibraryTree.build([
      book('משנה שבת', 'ספרות חז"ל > משנה', 2),
    ]);
    final folder = tree.folderFor('/משנה')!;
    // `ספרות חז"ל > משנה` נצרך כולו, ולכן אין תיקיות מתחת.
    expect(folder.subCategories, isEmpty);
    expect(folder.books.single.title, 'משנה שבת');
  });

  test('ספרים מאותה קטגוריה מתאחדים לתיקייה אחת', () {
    final tree = ResponsaLibraryTree.build([
      book('א', 'ספרי חסידות', 1),
      book('ב', 'ספרי חסידות', 2),
    ]);
    expect(tree.byCategoryPath.length, 1);
    expect(tree.folderFor('/חסידות')!.books.length, 2);
  });

  test('קטגוריה שאינה משויכת מקבלת תיקייה עליונה ולא נעלמת', () {
    final tree = ResponsaLibraryTree.build([
      book('ספר יתום', 'קטגוריה חדשה במהדורה הבאה', 9),
    ]);
    expect(tree.byCategoryPath, isEmpty);
    expect(tree.topLevel.single.title, ResponsaLibraryTree.folderTitle);
    expect(
      tree.topLevel.single.subCategories.single.title,
      'קטגוריה חדשה במהדורה הבאה',
    );
  });

  test('רשימה ריקה מחזירה עץ ריק', () {
    expect(ResponsaLibraryTree.build(const []).isEmpty, isTrue);
    expect(ResponsaLibraryTree.empty.isEmpty, isTrue);
  });

  test('התיקייה נשענת על Category.path של היעד', () {
    final tree = ResponsaLibraryTree.build([
      book('מדרש', 'ספרות חז"ל > מדרשי אגדה', 3),
    ]);
    // שני רכיבים — הנתיב חייב להיות מלא ולא רק השורש.
    expect(tree.folderFor('/מדרש/אגדה'), isNotNull);
    expect(tree.folderFor('/מדרש'), isNull);
  });
}

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

  test('ספר שו"ת של אחרונים נכנס לתיקייה בתוך שו״ת › אחרונים', () {
    final tree = ResponsaLibraryTree.build([
      book(
        'תורת יקותיאל אישות',
        'ספרי שאלות ותשובות (שו"ת) > ספרי שאלות ותשובות - אחרונים',
        1,
      ),
    ]);
    // שתי הרמות נצרכו, ולכן הספר יושב ישירות בתיקייה.
    final folder = tree.folderFor('/שו״ת/אחרונים');
    expect(folder, isNotNull);
    expect(folder!.title, ResponsaLibraryTree.folderTitle);
    expect(folder.books.single.title, 'תורת יקותיאל אישות');
    // ולא בשורש `שו״ת`, שבו יושבים רק מדפים שלא פורטו.
    expect(tree.folderFor('/שו״ת'), isNull);
  });

  test('תו גרשיים אחר בשם הקטגוריה אינו מנתק את התיקייה', () {
    // `Category.path` נבנה מכותרות הספרייה המותקנת. בלי נרמול, ספרייה
    // שכותרתה `שו"ת` ב-ASCII הייתה מאבדת את כל אלף הספרים בשקט.
    final tree = ResponsaLibraryTree.build([
      book('תורת יקותיאל אישות', 'ספרי שאלות ותשובות (שו"ת)', 1),
    ]);
    expect(tree.folderFor('/שו״ת'), isNotNull);
    expect(tree.folderFor('/שו"ת'), isNotNull);
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

  /// בלי המזהה תיקיית בר אילן מקבלת את אייקון התיקייה הרגיל, ויושבת
  /// בתוך `שו״ת › אחרונים` כשכנה זהה לתיקייה של ספרים מותקנים.
  test('כל תיקייה בעץ נושאת את מזהה הספק, כולל תיקיות הבת', () {
    final tree = ResponsaLibraryTree.build([
      book('מדרש', 'ספרות חז"ל > מדרשי אגדה > מדרש רבה', 3),
      book('ספר יתום', 'קטגוריה חדשה במהדורה הבאה', 9),
    ]);
    final roots = [...tree.byCategoryPath.values, ...tree.topLevel];
    expect(roots, hasLength(2));
    for (final root in roots) {
      for (final folder in [root, ...root.getAllCategories()]) {
        expect(folder.externalProviderId, 'responsa', reason: folder.title);
      }
    }
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

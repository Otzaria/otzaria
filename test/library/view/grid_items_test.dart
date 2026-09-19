import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

class _FakeFileSystemData extends FileSystemData {
  _FakeFileSystemData({this.canDelete = false});

  /// האם מחיקה מהספרייה מותרת (מדמה ספר "עותק עצמאי" כשהוא true).
  final bool canDelete;

  @override
  Future<bool> canDeleteUserBookFromLibrary({
    required String title,
    int? categoryId,
    String fileType = 'txt',
    required BookSource source,
  }) async {
    return canDelete;
  }
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileSystemData originalFileSystemData;

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    originalFileSystemData = FileSystemData.instance;
  });

  setUp(() {
    // ברירת מחדל: מחיקה מהספרייה אסורה (כמו ספר רשמי / קריאה מהקבצים).
    FileSystemData.instance = _FakeFileSystemData(canDelete: false);
  });

  tearDown(() {
    FileSystemData.instance = originalFileSystemData;
  });

  Widget buildTestWidget({
    required Book book,
    bool showTopics = false,
    double width = 260,
  }) {
    return MaterialApp(
      home: Material(
        child: Center(
          child: SizedBox(
            width: width,
            child: BookGridItem(
              book: book,
              showTopics: showTopics,
              onBookClickCallback: () {},
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCategoryTestWidget(Category category) {
    return MaterialApp(
      home: Material(
        child: Center(
          child: SizedBox(
            width: 260,
            child: CategoryGridItem(
              category: category,
              onCategoryClickCallback: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('מציג tooltip כשהכותרת נחתכת עם ellipsis בתוך המילה האחרונה', (
    tester,
  ) async {
    final book = PdfBook(
      title: 'ספר עם שם ארוך מאודמאודשנחתךבאמצעהמילה',
      path: r'C:\library\folder\book.pdf',
      categoryPath: 'קטגוריה/פנימית/ארוכה',
    );

    await tester.pumpWidget(buildTestWidget(book: book, width: 180));
    await tester.pumpAndSettle();

    expect(find.byType(Tooltip), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.preferBelow, isFalse);
    expect(tooltip.verticalOffset, 18);
  });

  testWidgets('בתוצאות חיפוש מוצג נתיב הקטגוריות, לא הנושאים', (
    tester,
  ) async {
    const categoryPath = 'קטגוריה ראשית, קטגוריה משנית, נתיב מלא וארוך מאוד';
    final book = PdfBook(
      title: 'א',
      path: r'C:\library\folder\book.pdf',
      topics: 'נתיב ארוך מאוד מאוד שנחתך בתצוגת הספריה ומחייב tooltip',
      categoryPath: categoryPath,
    );

    await tester.pumpWidget(
      buildTestWidget(book: book, showTopics: true, width: 220),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(categoryPath), findsOneWidget);
    expect(find.byTooltip('א'), findsNothing);
  });

  testWidgets('בלי נתיב קטגוריות מוצגים הנושאים', (tester) async {
    const topics = 'נתיב ארוך מאוד מאוד שנחתך בתצוגת הספריה ומחייב tooltip';
    final book = PdfBook(
      title: 'א',
      path: r'C:\library\folder\book.pdf',
      topics: topics,
    );

    await tester.pumpWidget(
      buildTestWidget(book: book, showTopics: true, width: 220),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(topics), findsOneWidget);
  });

  test('מקצר תיאור ספר ל-120 תווים כולל שלוש נקודות', () {
    final description = List.filled(121, 'א').join();

    final result = truncateBookCardDescription(description);

    expect(result.length, kBookCardDescriptionMaxCharacters);
    expect(result, '${List.filled(117, 'א').join()}...');
  });

  testWidgets(
    'זמני: אינו מציג תיאור קצר בכרטיס, והתיאור המורחב נשאר בריחוף על כפתור המידע',
    (tester) async {
      const shortDescription = 'תיאור קצר שאינו מוצג בכרטיס';
      const fullDescription = 'תיאור ארוך שמוצג בריחוף על כפתור המידע בלבד';
      final book = TextBook(
        title: 'ספר מידע',
        heShortDesc: shortDescription,
        heDesc: fullDescription,
      );

      await tester.pumpWidget(buildTestWidget(book: book));
      await tester.pumpAndSettle();

      expect(find.text(shortDescription), findsNothing);
      expect(
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message),
        contains(fullDescription),
      );
    },
  );

  testWidgets('לחיצה על כפתור המידע פותחת את חלון אודות הספר', (tester) async {
    final book = TextBook(
      title: 'ספר מידע',
      heShortDesc: 'תיאור קצר',
      heDesc: 'תיאור ארוך',
    );

    await tester.pumpWidget(buildTestWidget(book: book));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.info_24_regular));
    await tester.pump();

    expect(find.text('אודות הספר'), findsOneWidget);
  });

  testWidgets('מציג פעולת מחיקה עבור ספר "עותק עצמאי"', (tester) async {
    // עותק עצמאי (content-in-db) — ניתן למחיקה מהספרייה.
    FileSystemData.instance = _FakeFileSystemData(canDelete: true);

    final book = TextBook(
      title: 'ספר עצמאי לבדיקה',
      categoryId: 42,
      source: BookSource.user,
    );

    await tester.pumpWidget(buildTestWidget(book: book));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(FluentIcons.more_vertical_24_regular),
      findsOneWidget,
    );
  });

  testWidgets('לא מציג פעולת מחיקה עבור ספר "קריאה מהקבצים"', (tester) async {
    // קריאה מהקבצים (file-backed) — נמחק רק מהדיסק, לא מהספרייה.
    FileSystemData.instance = _FakeFileSystemData(canDelete: false);

    final book = TextBook(
      title: 'ספר מקובץ לבדיקה',
      categoryId: 7,
      source: BookSource.user,
    );

    await tester.pumpWidget(buildTestWidget(book: book));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(FluentIcons.more_vertical_24_regular),
      findsNothing,
    );
  });

  testWidgets('מציג את אייקון הקובץ ותפריט האפשרויות בטור אנכי', (
    tester,
  ) async {
    FileSystemData.instance = _FakeFileSystemData(canDelete: true);

    final book = TextBook(
      title: 'ספר לבדיקה',
      categoryId: 11,
      source: BookSource.user,
    );

    await tester.pumpWidget(buildTestWidget(book: book));
    await tester.pumpAndSettle();

    final fileIconCenter = tester.getCenter(
      find.byIcon(FluentIcons.document_text_24_regular),
    );
    final menuIconCenter = tester.getCenter(
      find.byIcon(FluentIcons.more_vertical_24_regular),
    );

    expect((fileIconCenter.dx - menuIconCenter.dx).abs(), lessThan(2));
    expect(menuIconCenter.dy, greaterThan(fileIconCenter.dy));
  });

  testWidgets('קובץ Word (docx) מקבל אייקון ייעודי נבדל מספר טקסט', (
    tester,
  ) async {
    final book = DocxBook(title: 'מסמך וורד', path: r'C:\library\doc.docx');

    await tester.pumpWidget(buildTestWidget(book: book));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.document_edit_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.document_text_24_regular), findsNothing);
  });

  testWidgets('מציג אייקון תיקייה בקו regular ולא filled', (tester) async {
    final category = Category(
      title: 'קטגוריה',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 260,
              child: CategoryGridItem(
                category: category,
                onCategoryClickCallback: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.folder_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.folder_24_filled), findsNothing);
  });

  group('מידע קטגוריה', () {
    Category category({
      String shortDescription = '',
      String description = '',
    }) {
      return Category(
        title: 'קטגוריית בדיקה',
        description: description,
        shortDescription: shortDescription,
        order: 0,
        subCategories: [],
        books: [],
        parent: null,
      );
    }

    Finder infoButton() =>
        find.widgetWithIcon(IconButton, FluentIcons.info_24_regular);

    Future<void> closeDialog(WidgetTester tester) async {
      await tester.tap(find.text('סגור'));
      await tester.pumpAndSettle();
      expect(find.text('אודות הקטגוריה'), findsNothing);
    }

    testWidgets('קצר וארוך: הקצר אינו בכרטיס (זמני), הארוך בריחוף ובדיאלוג', (
      tester,
    ) async {
      final item = category(
        shortDescription: 'תיאור קצר',
        description: 'תיאור מורחב',
      );

      await tester.pumpWidget(buildCategoryTestWidget(item));
      await tester.pumpAndSettle();

      expect(find.text('תיאור קצר'), findsNothing);
      expect(
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message),
        contains('תיאור מורחב'),
      );
      expect(infoButton(), findsOneWidget);

      await tester.tap(infoButton());
      await tester.pumpAndSettle();

      expect(find.text('אודות הקטגוריה'), findsOneWidget);
      expect(find.text('שם הקטגוריה:'), findsOneWidget);
      expect(find.text('קטגוריית בדיקה'), findsNWidgets(2));
      expect(find.text('תיאור קצר:'), findsOneWidget);
      expect(find.text('תיאור קצר'), findsOneWidget);
      expect(find.text('תיאור מורחב:'), findsOneWidget);
      expect(find.text('תיאור מורחב'), findsOneWidget);
      await closeDialog(tester);
    });

    testWidgets('קצר בלבד: אינו בכרטיס (זמני), משמש בריחוף ובדיאלוג', (
      tester,
    ) async {
      final item = category(shortDescription: 'תיאור קצר בלבד');

      await tester.pumpWidget(buildCategoryTestWidget(item));
      await tester.pumpAndSettle();

      expect(find.text('תיאור קצר בלבד'), findsNothing);
      expect(
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message),
        contains('תיאור קצר בלבד'),
      );
      expect(infoButton(), findsOneWidget);

      await tester.tap(infoButton());
      await tester.pumpAndSettle();

      expect(find.text('אודות הקטגוריה'), findsOneWidget);
      expect(find.text('תיאור קצר:'), findsOneWidget);
      expect(find.text('תיאור קצר בלבד'), findsOneWidget);
      expect(find.text('תיאור מורחב:'), findsNothing);
      await closeDialog(tester);
    });

    testWidgets('ארוך בלבד: אינו מציג קצר בכרטיס אך מאפשר מידע מלא', (
      tester,
    ) async {
      final item = category(description: 'תיאור מורחב בלבד');

      await tester.pumpWidget(buildCategoryTestWidget(item));
      await tester.pumpAndSettle();

      expect(find.text('תיאור מורחב בלבד'), findsNothing);
      expect(
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message),
        contains('תיאור מורחב בלבד'),
      );
      expect(infoButton(), findsOneWidget);

      await tester.tap(infoButton());
      await tester.pumpAndSettle();

      expect(find.text('אודות הקטגוריה'), findsOneWidget);
      expect(find.text('תיאור קצר:'), findsNothing);
      expect(find.text('תיאור מורחב:'), findsOneWidget);
      expect(find.text('תיאור מורחב בלבד'), findsOneWidget);
      await closeDialog(tester);
    });

    testWidgets('ללא תיאורים: אינו מציג לחצן מידע או דיאלוג', (tester) async {
      await tester.pumpWidget(buildCategoryTestWidget(category()));
      await tester.pumpAndSettle();

      expect(infoButton(), findsNothing);
      expect(
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message),
        isNot(contains('')),
      );
      expect(find.text('אודות הקטגוריה'), findsNothing);
    });
  });

  group('externalCatalogLogoAsset', () {
    test('ספר היברובוקס מקומי (PdfBook עם hb:) מקבל לוגו היברובוקס', () {
      final book = PdfBook(
        title: 'ספר',
        path: r'C:\hb\Hebrewbooks_org_123.pdf',
        externalLibraryId: 'hb:123',
      );
      expect(externalCatalogLogoAsset(book), 'assets/logos/hebrew_books.png');
    });

    test('ספר PDF מקומי רגיל ללא מקור חיצוני אינו מקבל לוגו', () {
      // הנתיב מכיל "otzaria" (תיקיית התוכנה) ואסור שיגרום לזיהוי שגוי.
      final book = PdfBook(
        title: 'ספר',
        path: r'C:\Users\x\AppData\Roaming\otzaria\books\ספר.pdf',
      );
      expect(externalCatalogLogoAsset(book), isNull);
    });

    test('ספר היברובוקס חיצוני מקבל לוגו לפי הקישור', () {
      final book = ExternalLibraryBook(
        title: 'ספר',
        id: 5,
        author: '',
        link: 'https://hebrewbooks.org/5',
      );
      expect(externalCatalogLogoAsset(book), 'assets/logos/hebrew_books.png');
    });

    test('ספר אוצר החכמה חיצוני מקבל לוגו אוצר', () {
      final book = ExternalLibraryBook(
        title: 'ספר',
        id: 7,
        author: '',
        link: 'https://tablet.otzar.org/book/book.php?book=7',
      );
      expect(externalCatalogLogoAsset(book), 'assets/logos/otzar.ico');
    });
  });

  group('MyGridView בתצוגה צרה', () {
    testWidgets('מקטין את גובה כרטיס הספר בחצי עם רצפת גובה לקריאה', (
      tester,
    ) async {
      final book = TextBook(
        title: 'שם ספר ארוך מאוד שמתפרס על שתי שורות בכרטיס',
        author: 'מחבר ארוך מאוד שמתפרס על שתי שורות',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: MyGridView(
                items: [
                  BookGridItem(book: book, onBookClickCallback: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // רוחב הרשת: 400 - 60 (שוליים 30+30) = 340. הגובה הקודם היה
      // 340/1.65 ≈ 206, והחדש נחתך לחצי עם רצפה של 112 — בלי גלישה.
      final size = tester.getSize(find.byType(BookGridItem));
      expect(size.width, closeTo(340, 0.5));
      expect(size.height, closeTo(kNarrowGridCardMinHeight, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('בתצוגה רחבה הגובה נשאר ללא שינוי', (tester) async {
      // משטח ברירת המחדל הוא 800×600 וחותך את הרוחב — מרחיבים אותו.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final book = TextBook(title: 'ספר', author: 'מחבר');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: MyGridView(
                items: [
                  BookGridItem(book: book, onBookClickCallback: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 4 עמודות, רוחב תא (1000 - 60 - 14*3)/4 = 224.5, יחס 1.8 → גובה ≈ 125.
      final size = tester.getSize(find.byType(BookGridItem));
      expect(size.height, closeTo(224.5 / 1.8, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('סף 800px מעביר בין פריסת צרה לרחבה', (tester) async {
      final book = TextBook(title: 'ספר', author: 'מחבר');

      Future<Size> pumpAtWidth(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: MyGridView(
                  items: [BookGridItem(book: book, onBookClickCallback: () {})],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(BookGridItem));
      }

      final narrowSize = await pumpAtWidth(799);
      expect(narrowSize.height, closeTo(kNarrowGridCardMinHeight, 0.5));

      final wideSize = await pumpAtWidth(800);
      final wideCellWidth = (800 - 60 - 14 * 2) / 3;
      expect(wideSize.height, closeTo(wideCellWidth / 1.8, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('רצפת הגובה גדלה עם מידת הטקסט', (tester) async {
      final book = TextBook(
        title: 'שם ספר ארוך מאוד שמתפרס על שתי שורות בכרטיס',
        author: 'מחבר ארוך מאוד שמתפרס על שתי שורות',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 400,
                child: MyGridView(
                  items: [BookGridItem(book: book, onBookClickCallback: () {})],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(BookGridItem));
      expect(size.height, closeTo(kNarrowGridCardMinHeight * 2, 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  // תפריט "אפשרויות נוספות" משותף לכרטיס הרשת ולשורת העץ (issue #1256).
  group('BookActionsMenuButton', () {
    Widget buildMenu(Book book) => MaterialApp(
      home: Material(
        child: Center(
          child: BookActionsMenuButton(book: book, onBookDeleted: () {}),
        ),
      ),
    );

    testWidgets('מציג את התפריט ואת פעולת המחיקה לספר "עותק עצמאי"', (
      tester,
    ) async {
      FileSystemData.instance = _FakeFileSystemData(canDelete: true);
      final book = TextBook(
        title: 'ספר עצמאי',
        categoryId: 3,
        source: BookSource.user,
      );

      await tester.pumpWidget(buildMenu(book));
      await tester.pumpAndSettle();

      expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      expect(find.text('מחק מהספרייה'), findsOneWidget);
    });

    testWidgets('נעלם כשאין פעולה זמינה', (tester) async {
      FileSystemData.instance = _FakeFileSystemData(canDelete: false);
      final book = TextBook(
        title: 'ספר מקובץ',
        categoryId: 4,
        source: BookSource.user,
      );

      await tester.pumpWidget(buildMenu(book));
      await tester.pumpAndSettle();

      expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsNothing);
    });
  });
}

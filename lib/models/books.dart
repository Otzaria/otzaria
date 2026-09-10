import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/book_toc_loader.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/file/document_format.dart';

//import 'package:pdfrx/pdfrx.dart';

/// Represents a book in the application.
///
/// A `Book` object has a [title] which is the name of the book,
/// and an [author], [heShortDesc], [pubPlace], [pubDate], and [order] if available.
///
abstract class Book {
  /// The unique identifier of the book from the database (if available)
  final int? id;

  /// The title of the book.
  final String title;

  final Category? category;

  /// Additional titles of the book, if available.
  final List<String>? extraTitles;

  /// The author of the book, if available.
  String? author;

  /// Categories in Hebrew
  String? heCategories;

  /// Era in Hebrew
  String? heEra;

  /// Composition date string in Hebrew
  String? compDateStringHe;

  /// Composition place string in Hebrew
  String? compPlaceStringHe;

  /// Publication date string in Hebrew
  String? pubDateStringHe;

  /// Publication place string in Hebrew
  String? pubPlaceStringHe;

  /// A short description of the book, if available.
  String? heShortDesc;

  /// A full description of the book, if available.
  String? heDesc;

  /// The publication date of the book, if available.
  String? pubDate;

  /// The place where the book was published, if available.
  String? pubPlace;

  /// The order of the book in the list of books. If not available, defaults to 999.
  int order;

  String topics;

  String? filePath;

  String? fileType;

  String? categoryPath;

  /// The database category ID (if available)
  final int? categoryId;

  /// Whether this book was added by the user (true) or is part of the library (false).
  final bool isUserBook;

  /// External library ID (e.g., Sefaria ref) for books from external sources
  final String? externalLibraryId;

  Map<String, dynamic> toJson();

  factory Book.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'TextBook':
        return TextBook.fromJson(json);
      case 'PdfBook':
        return PdfBook.fromJson(json);
      case 'DocxBook':
        return DocxBook.fromJson(json);
      case 'EpubBook':
        return EpubBook.fromJson(json);
      case 'DocumentBook':
        return DocumentBook.fromJson(json);
      case 'ExternalLibraryBook':
        return ExternalLibraryBook.fromJson(json);
      default:
        throw Exception('Unknown book type: ${json['type']}');
    }
  }

  /// Creates a new `Book` instance.
  ///
  /// The [title] parameter is required and cannot be null.
  Book({
    this.id,
    required this.title,
    this.category,
    this.author,
    this.heCategories,
    this.heEra,
    this.compDateStringHe,
    this.compPlaceStringHe,
    this.pubDateStringHe,
    this.pubPlaceStringHe,
    this.heShortDesc,
    this.heDesc,
    this.pubDate,
    this.pubPlace,
    this.order = 999,
    this.topics = '',
    this.filePath,
    this.fileType,
    this.categoryPath,
    this.categoryId,
    this.extraTitles,
    this.isUserBook = false,
    this.externalLibraryId,
  });
}

///a representation of a text book (opposite PDF book).
///a text book has a getter 'text' which returns a [Future] that resolvs to a [String].
///it has also a 'tableOfContents' field that returns a [Future] that resolvs to a list of [TocEntry]s
class TextBook extends Book {
  /// כשלא null — הספר נפתח כמהדורה חלופית (book_version בשם זה) והתוכן
  /// נטען מ-version_line במקום הטקסט הממוזג.
  final String? versionTitle;

  /// שם המהדורה לתצוגה. [versionTitle] הוא מפתח ה-DB של ספריא ולרוב אנגלי,
  /// ולכן אינו מוצג למשתמש כשיש שם עברי.
  final String? heVersionTitle;

  TextBook({
    super.id,
    required super.title,
    super.category,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.heShortDesc,
    super.heDesc,
    super.pubDate,
    super.pubPlace,
    super.order = 999,
    super.topics,
    super.filePath,
    super.fileType = 'txt',
    super.categoryPath,
    super.categoryId,
    super.extraTitles,
    super.isUserBook,
    super.externalLibraryId,
    this.versionTitle,
    this.heVersionTitle,
  });

  /// שם המהדורה כפי שמוצג למשתמש, או null בנוסח הממוזג.
  String? get versionDisplayTitle => heVersionTitle ?? versionTitle;

  /// Retrieves the table of contents of the book.
  ///
  /// Returns a [Future] that resolves to a [List] of [TocEntry] objects representing
  /// the table of contents of the book.
  Future<List<TocEntry>> get tableOfContents => loadBookToc(this);

  /// Retrieves all the links for the book.
  ///
  /// Returns a [Future] that resolves to a [List] of [Link] objects.
  Future<List<Link>> get links async {
    final provider = LibraryProviderManager.instance.getProviderForBook(
      title,
      categoryId: categoryId,
      fileType: fileType ?? 'txt',
    );
    if (provider != null && categoryId != null) {
      return await provider.getAllLinksForBook(
        title,
        categoryId!,
        fileType ?? 'txt',
      );
    }
    return [];
  }

  /// The text data of the book.
  Future<String> get text async {
    final bookText = await LibraryProviderManager.instance.getBookText(
      title,
      categoryId: categoryId,
      fileType: fileType ?? 'txt',
      preferUserBooks: isUserBook,
    );
    return bookText ?? '';
  }

  /// יוצר עותק של הספר עם שדות מעודכנים לפי הצורך.
  TextBook copyWith({
    int? id,
    String? heCategories,
    String? author,
    String? heEra,
    String? versionTitle,
    String? heVersionTitle,
  }) {
    return TextBook(
      id: id ?? this.id,
      title: title,
      category: category,
      author: author ?? this.author,
      heCategories: heCategories ?? this.heCategories,
      heEra: heEra ?? this.heEra,
      compDateStringHe: compDateStringHe,
      compPlaceStringHe: compPlaceStringHe,
      pubDateStringHe: pubDateStringHe,
      pubPlaceStringHe: pubPlaceStringHe,
      heShortDesc: heShortDesc,
      heDesc: heDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      filePath: filePath,
      fileType: fileType,
      categoryPath: categoryPath,
      categoryId: categoryId,
      extraTitles: extraTitles,
      isUserBook: isUserBook,
      externalLibraryId: externalLibraryId,
      versionTitle: versionTitle ?? this.versionTitle,
      heVersionTitle: heVersionTitle ?? this.heVersionTitle,
    );
  }

  /// Creates a new `Book` instance from a JSON object.
  ///
  /// The JSON object should have a 'title' key.
  factory TextBook.fromJson(Map<String, dynamic> json) {
    return TextBook(
      id: json['id'],
      title: json['title'],
      author: json['author'],
      filePath: json['filePath'],
      categoryPath: json['categoryPath'],
      categoryId: json['categoryId'],
      fileType: json['fileType'],
      heCategories: json['heCategories'],
      heEra: json['heEra'],
      isUserBook: json['isUserBook'] ?? false,
      externalLibraryId: json['externalLibraryId'],
      versionTitle: json['versionTitle'],
      heVersionTitle: json['heVersionTitle'],
    );
  }

  /// Converts the `Book` instance into a JSON object.
  ///
  /// Returns a JSON object with a 'title' key.
  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': 'TextBook',
      'author': author,
      'filePath': filePath,
      'fileType': fileType,
      'categoryPath': categoryPath,
      'categoryId': categoryId,
      'heCategories': heCategories,
      'heEra': heEra,
      'isUserBook': isUserBook,
      'externalLibraryId': externalLibraryId,
      'versionTitle': versionTitle,
      'heVersionTitle': heVersionTitle,
    };
  }
}

/// Represents a book from the Otzar HaChochma digital library.
///
/// This class extends the [Book] class and includes additional properties
/// specific to Otzar HaChochma books, such as the Otzar ID and online link.
class ExternalLibraryBook extends Book {
  /// The online link to access the book in the Otzar HaChochma system.
  final String link;

  /// Creates an [ExternalLibraryBook] instance.
  ///
  /// [title] and [id] are required. Other parameters are optional.
  /// [link] is required for online access to the book.
  ExternalLibraryBook({
    required super.title,
    required int id,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.pubPlace,
    super.pubDate,
    super.topics,
    super.heShortDesc,
    super.heDesc,
    required this.link,
    super.categoryPath,
    super.categoryId,
    super.fileType = 'link',
    super.isUserBook,
    super.externalLibraryId,
  }) : super(id: id);

  /// Returns the publication date of the book.
  ///

  /// Creates an [ExternalLibraryBook] instance from a JSON map.
  ///
  /// This factory constructor is used to deserialize OtzarBook objects.
  factory ExternalLibraryBook.fromJson(Map<String, dynamic> json) {
    return ExternalLibraryBook(
      title: json['bookName'] ?? json['title'],
      id: json['id'] ?? json['otzarId'],
      author: json['author'],
      pubPlace: json['pubPlace'],
      pubDate: json['pubDate'],
      topics: json['topics'] ?? '',
      categoryPath: json['categoryPath'],
      link: json['link'],
      heCategories: json['heCategories'],
      isUserBook: json['isUserBook'] ?? false,
      externalLibraryId: json['externalLibraryId'],
    );
  }

  /// Converts the [ExternalLibraryBook] instance to a JSON map.
  ///
  /// This method is used to serialize OtzarBook objects.
  @override
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'type': 'ExternalLibraryBook',
      'otzarId': id,
      'author': author,
      'pubPlace': pubPlace,
      'pubDate': pubDate,
      'topics': topics,
      'link': link,
      'filePath': filePath,
      'categoryPath': categoryPath,
      'fileType': fileType,
      'heCategories': heCategories,
      'isUserBook': isUserBook,
      'externalLibraryId': externalLibraryId,
    };
  }
}

/// Abstract class for books that are based on a file in the file system.
abstract class FileBook extends Book {
  final String path;

  FileBook({
    super.id,
    required super.title,
    required this.path,
    super.category,
    super.topics,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.heShortDesc,
    super.heDesc,
    super.pubDate,
    super.pubPlace,
    super.categoryPath,
    super.categoryId,
    super.filePath,
    super.fileType,
    super.order = 999,
    super.isUserBook,
    super.externalLibraryId,
  });
}

///represents a PDF format book, which is always a file on the device, and there for the [String] fiels 'path'
///is required
class PdfBook extends FileBook {
  PdfBook({
    super.id,
    required super.title,
    super.category,
    required super.path,
    super.topics,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.heShortDesc,
    super.heDesc,
    super.pubDate,
    super.pubPlace,
    super.filePath,
    super.categoryPath,
    super.categoryId,
    super.fileType = 'pdf',
    super.order = 999,
    super.isUserBook,
    super.externalLibraryId,
  });

  factory PdfBook.fromJson(Map<String, dynamic> json) {
    return PdfBook(
      id: json['id'] as int?,
      title: json['title'],
      path: json['path'],
      author: json['author'],
      categoryPath: json['categoryPath'],
      filePath: json['filePath'],
      heCategories: json['heCategories'],
      heEra: json['heEra'],
      isUserBook: json['isUserBook'] ?? false,
      externalLibraryId: json['externalLibraryId'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'path': path,
      'type': 'PdfBook',
      'author': author,
      'filePath': filePath,
      'categoryPath': categoryPath,
      'fileType': fileType,
      'heCategories': heCategories,
      'heEra': heEra,
      'isUserBook': isUserBook,
      'externalLibraryId': externalLibraryId,
    };
  }

  @override
  String toString() => 'pdfBook(title: $title, path: $path)';
}

/// ספר שתוכנו יושב בקובץ ודורש המרה לפני הצגה (DOCX, EPUB, ODT…).
///
/// זהו הטיפוס שכל זרימה גנרית צריכה לבדוק מולו — `book is
/// ConvertibleDocumentBook` — במקום להוסיף ענף לכל פורמט חדש. הפורמט עצמו
/// נשמר ב-`fileType` ואינו נגזר מהמחלקה.
abstract class ConvertibleDocumentBook extends FileBook {
  ConvertibleDocumentBook({
    super.id,
    required super.title,
    super.category,
    required super.path,
    super.topics,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.heShortDesc,
    super.heDesc,
    super.pubDate,
    super.pubPlace,
    super.filePath,
    super.categoryPath,
    super.categoryId,
    super.fileType,
    super.order,
    super.isUserBook,
    super.externalLibraryId,
  });

  /// ה-`fileType` שישמש כשהשדה ריק — הסיומת הקנונית של הפורמט.
  String get fallbackFileType;

  /// עוטף את הספר ל-TextBook לטובת זרימות שעובדות מול TextBook (תצוגת טאב,
  /// פריוויו, אינדוקס).
  ///
  /// חובה לשמר `id`, `categoryId` ו-`externalLibraryId` — בלעדיהם
  /// `LibraryProviderManager.getBookText` לא מאתר את הספר ב-cache (המפתח שלו
  /// הוא title+categoryId+fileType) והתוכן יוצא ריק. `filePath` נופל ל-`path`
  /// כשאינו מוגדר, כדי שזרימת `getBookText` תזהה את הקובץ ותפעיל את הממיר.
  TextBook toTextBook() {
    return TextBook(
      id: id,
      title: title,
      category: category,
      author: author,
      heCategories: heCategories,
      heEra: heEra,
      compDateStringHe: compDateStringHe,
      compPlaceStringHe: compPlaceStringHe,
      pubDateStringHe: pubDateStringHe,
      pubPlaceStringHe: pubPlaceStringHe,
      heShortDesc: heShortDesc,
      heDesc: heDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      filePath: filePath ?? path,
      fileType: fileType ?? fallbackFileType,
      categoryPath: categoryPath,
      categoryId: categoryId,
      extraTitles: extraTitles,
      isUserBook: isUserBook,
      externalLibraryId: externalLibraryId,
    );
  }
}

/// Represents a DOCX format book.
class DocxBook extends ConvertibleDocumentBook {
  DocxBook({
    super.id,
    required super.title,
    super.category,
    required super.path,
    super.topics,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.heShortDesc,
    super.heDesc,
    super.pubDate,
    super.pubPlace,
    super.filePath,
    super.categoryPath,
    super.categoryId,
    super.fileType = 'docx',
    super.order = 999,
    super.isUserBook,
    super.externalLibraryId,
  });

  factory DocxBook.fromJson(Map<String, dynamic> json) {
    return DocxBook(
      title: json['title'],
      path: json['path'],
      author: json['author'],
      filePath: json['filePath'],
      categoryPath: json['categoryPath'],
      heCategories: json['heCategories'],
      heEra: json['heEra'],
      isUserBook: json['isUserBook'] ?? false,
      externalLibraryId: json['externalLibraryId'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'path': path,
      'type': 'DocxBook',
      'author': author,
      'filePath': filePath,
      'fileType': fileType,
      'categoryPath': categoryPath,
      'heCategories': heCategories,
      'heEra': heEra,
      'isUserBook': isUserBook,
      'externalLibraryId': externalLibraryId,
    };
  }

  @override
  String toString() => 'DocxBook(title: $title, path: $path)';

  @override
  String get fallbackFileType => 'docx';
}

/// Represents an EPUB format book.
class EpubBook extends ConvertibleDocumentBook {
  EpubBook({
    super.id,
    required super.title,
    super.category,
    required super.path,
    super.topics,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.heShortDesc,
    super.heDesc,
    super.pubDate,
    super.pubPlace,
    super.filePath,
    super.categoryPath,
    super.categoryId,
    super.fileType = 'epub',
    super.order = 999,
    super.isUserBook,
    super.externalLibraryId,
  });

  factory EpubBook.fromJson(Map<String, dynamic> json) {
    return EpubBook(
      id: json['id'] as int?,
      title: json['title'] as String,
      path: json['path'] as String,
      author: json['author'] as String?,
      filePath: json['filePath'] as String?,
      categoryPath: json['categoryPath'] as String?,
      categoryId: json['categoryId'] as int?,
      heCategories: json['heCategories'] as String?,
      heEra: json['heEra'] as String?,
      isUserBook: json['isUserBook'] as bool? ?? false,
      externalLibraryId: json['externalLibraryId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'path': path,
      'type': 'EpubBook',
      'author': author,
      'filePath': filePath,
      'fileType': fileType,
      'categoryPath': categoryPath,
      'categoryId': categoryId,
      'heCategories': heCategories,
      'heEra': heEra,
      'isUserBook': isUserBook,
      'externalLibraryId': externalLibraryId,
    };
  }

  @override
  String toString() => 'EpubBook(title: $title, path: $path)';

  @override
  String get fallbackFileType => 'epub';
}

/// ספר מסמך גנרי לפורמטים שאין להם מחלקה ייעודית (ODT, RTF, DOCM…).
///
/// אין ליצור מחלקה נפרדת לכל סיומת — הן אינן נבדלות בהתנהגות אלא רק בממיר,
/// והממיר נבחר לפי `fileType`. `type` בסיריאליזציה הוא `DocumentBook`,
/// ו-`fileType` נשמר כפי שהוא כדי שזהות הספר תשרוד restart.
class DocumentBook extends ConvertibleDocumentBook {
  DocumentBook({
    super.id,
    required super.title,
    super.category,
    required super.path,
    super.topics,
    super.author,
    super.heCategories,
    super.heEra,
    super.compDateStringHe,
    super.compPlaceStringHe,
    super.pubDateStringHe,
    super.pubPlaceStringHe,
    super.heShortDesc,
    super.heDesc,
    super.pubDate,
    super.pubPlace,
    super.filePath,
    super.categoryPath,
    super.categoryId,
    required String super.fileType,
    super.order = 999,
    super.isUserBook,
    super.externalLibraryId,
  });

  factory DocumentBook.fromJson(Map<String, dynamic> json) {
    return DocumentBook(
      id: json['id'] as int?,
      title: json['title'] as String,
      path: json['path'] as String,
      author: json['author'] as String?,
      filePath: json['filePath'] as String?,
      categoryPath: json['categoryPath'] as String?,
      categoryId: json['categoryId'] as int?,
      heCategories: json['heCategories'] as String?,
      heEra: json['heEra'] as String?,
      fileType: json['fileType'] as String,
      isUserBook: json['isUserBook'] as bool? ?? false,
      externalLibraryId: json['externalLibraryId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'path': path,
      'type': 'DocumentBook',
      'author': author,
      'filePath': filePath,
      'fileType': fileType,
      'categoryPath': categoryPath,
      'categoryId': categoryId,
      'heCategories': heCategories,
      'heEra': heEra,
      'isUserBook': isUserBook,
      'externalLibraryId': externalLibraryId,
    };
  }

  @override
  String toString() => 'DocumentBook(title: $title, fileType: $fileType)';

  @override
  String get fallbackFileType => fileType!;
}

///represents an entry in table of content , which is a node in a hirarchial tree of topics.
///every entry has its 'level' in the tree, and an index of the line in the book that it is refers to
class TocEntry {
  final String text;
  final int index;
  final int level;
  final TocEntry? parent;
  List<TocEntry> children = [];
  String get fullText => () {
    TocEntry? parent = this.parent;
    String text = this.text;
    while (parent != null && parent.level > 1) {
      if (parent.text != '') {
        text = '${parent.text}, $text';
      }
      parent = parent.parent;
    }
    return text;
  }();

  ///creats [TocEntry]
  TocEntry({
    required this.text,
    required this.index,
    this.level = 1,
    this.parent,
  });
}

/// משטח עץ [TocEntry] לרשימה אחת (pre-order), כולל כל הצאצאים.
/// נחוץ למי שמחפש כותרת בכל העץ — `tableOfContents` מחזיר רק את שורשי העץ.
List<TocEntry> flattenToc(List<TocEntry> entries) {
  final flat = <TocEntry>[];
  void visit(TocEntry e) {
    flat.add(e);
    for (final child in e.children) {
      visit(child);
    }
  }

  for (final e in entries) {
    visit(e);
  }
  return flat;
}

/// בונה את מחלקת הספר המתאימה לפורמט — נקודת ההחלטה **היחידה** בין
/// `fileType` למחלקה.
///
/// `DocxBook`/`EpubBook` נשמרות כדי שסיריאליזציה של טאבים והיסטוריה קיימים
/// תמשיך להיפתח; כל פורמט מומר אחר מקבל [DocumentBook] עם `fileType` משלו.
Book buildBookForFileType({
  required String? fileType,
  int? id,
  required String title,
  Category? category,
  required String path,
  String? filePath,
  String? author,
  String? heCategories,
  String? heEra,
  String? heShortDesc,
  String? heDesc,
  String? pubDate,
  String? pubPlace,
  int order = 999,
  String topics = '',
  String? categoryPath,
  int? categoryId,
  List<String>? extraTitles,
  bool isUserBook = false,
  String? externalLibraryId,
}) {
  // הסיומת נלקחת מנתיב **הקובץ** בלבד: בספר שאין לו קובץ, `path` הוא כותרת
  // הספר, ונקודה בכותרת אינה סיומת.
  final format = documentFormatOf(fileType: fileType, path: filePath);
  final resolvedType = format?.extension ?? 'txt';

  // בלי קובץ אין מה להמיר — הספר נטען משורות ה-DB ולכן נשאר TextBook,
  // אך `fileType` נשמר כדי שזהות הספר לא תשתנה.
  if (filePath == null) {
    return TextBook(
      id: id,
      title: title,
      category: category,
      author: author,
      heCategories: heCategories,
      heEra: heEra,
      heShortDesc: heShortDesc,
      heDesc: heDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      fileType: resolvedType,
      categoryPath: categoryPath,
      categoryId: categoryId,
      extraTitles: extraTitles,
      isUserBook: isUserBook,
      externalLibraryId: externalLibraryId,
    );
  }

  if (format == DocumentFormat.pdf) {
    return PdfBook(
      id: id,
      title: title,
      category: category,
      path: path,
      filePath: filePath,
      author: author,
      heCategories: heCategories,
      heEra: heEra,
      heShortDesc: heShortDesc,
      heDesc: heDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      categoryPath: categoryPath,
      categoryId: categoryId,
      isUserBook: isUserBook,
      externalLibraryId: externalLibraryId,
    );
  }

  if (format == DocumentFormat.docx) {
    return DocxBook(
      id: id,
      title: title,
      category: category,
      path: path,
      filePath: filePath,
      author: author,
      heCategories: heCategories,
      heEra: heEra,
      heShortDesc: heShortDesc,
      heDesc: heDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      categoryPath: categoryPath,
      categoryId: categoryId,
      isUserBook: isUserBook,
      externalLibraryId: externalLibraryId,
    );
  }

  if (format == DocumentFormat.epub) {
    return EpubBook(
      id: id,
      title: title,
      category: category,
      path: path,
      filePath: filePath,
      author: author,
      heCategories: heCategories,
      heEra: heEra,
      heShortDesc: heShortDesc,
      heDesc: heDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      categoryPath: categoryPath,
      categoryId: categoryId,
      isUserBook: isUserBook,
      externalLibraryId: externalLibraryId,
    );
  }

  if (format == null || !format.isDocumentBook) {
    return TextBook(
      id: id,
      title: title,
      category: category,
      author: author,
      heCategories: heCategories,
      heEra: heEra,
      heShortDesc: heShortDesc,
      heDesc: heDesc,
      pubDate: pubDate,
      pubPlace: pubPlace,
      order: order,
      topics: topics,
      filePath: filePath,
      fileType: resolvedType,
      categoryPath: categoryPath,
      categoryId: categoryId,
      extraTitles: extraTitles,
      isUserBook: isUserBook,
      externalLibraryId: externalLibraryId,
    );
  }

  return DocumentBook(
    id: id,
    title: title,
    category: category,
    path: path,
    filePath: filePath,
    author: author,
    heCategories: heCategories,
    heEra: heEra,
    heShortDesc: heShortDesc,
    heDesc: heDesc,
    pubDate: pubDate,
    pubPlace: pubPlace,
    order: order,
    topics: topics,
    fileType: resolvedType,
    categoryPath: categoryPath,
    categoryId: categoryId,
    isUserBook: isUserBook,
    externalLibraryId: externalLibraryId,
  );
}

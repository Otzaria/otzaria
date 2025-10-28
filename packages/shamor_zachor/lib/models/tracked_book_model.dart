import 'package:shamor_zachor/models/book_model.dart';

/// Represents a book that is being tracked for learning progress
/// Can be either a built-in book or a custom user-added book
class TrackedBook {
  /// Unique identifier for the book (typically the book title/path)
  final String bookId;

  /// Display name of the book
  final String bookName;

  /// Category name (e.g., "תנך", "משנה", "רמב\"ם")
  final String categoryName;

  /// Whether this is a built-in book or user-added
  final bool isBuiltIn;

  /// Path to the book file in the library
  /// For built-in books, this is a predefined constant path
  /// For custom books, this is the actual path selected by the user
  final String bookPath;

  /// Book details including structure (parts, pages, etc.)
  final BookDetails bookDetails;

  /// The source file name (for built-in books, e.g., "tanach.json")
  final String sourceFile;

  /// Date when this book was added to tracking (ISO 8601 format)
  final DateTime dateAdded;

  /// Date when the book data was last scanned/updated
  final DateTime? lastScanned;

  const TrackedBook({
    required this.bookId,
    required this.bookName,
    required this.categoryName,
    required this.isBuiltIn,
    required this.bookPath,
    required this.bookDetails,
    required this.sourceFile,
    required this.dateAdded,
    this.lastScanned,
  });

  /// Create a TrackedBook from JSON
  factory TrackedBook.fromJson(Map<String, dynamic> json) {
    return TrackedBook(
      bookId: json['bookId'] as String,
      bookName: json['bookName'] as String,
      categoryName: json['categoryName'] as String,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      bookPath: json['bookPath'] as String,
      bookDetails: BookDetails.fromJson(
        json['bookDetails'] as Map<String, dynamic>,
        contentType: json['bookDetails']['contentType'] as String,
        isCustom: !(json['isBuiltIn'] as bool? ?? false),
      ),
      sourceFile: json['sourceFile'] as String,
      dateAdded: DateTime.parse(json['dateAdded'] as String),
      lastScanned: json['lastScanned'] != null
          ? DateTime.parse(json['lastScanned'] as String)
          : null,
    );
  }

  /// Convert TrackedBook to JSON
  Map<String, dynamic> toJson() {
    return {
      'bookId': bookId,
      'bookName': bookName,
      'categoryName': categoryName,
      'isBuiltIn': isBuiltIn,
      'bookPath': bookPath,
      'bookDetails': bookDetails.toJson(),
      'sourceFile': sourceFile,
      'dateAdded': dateAdded.toIso8601String(),
      if (lastScanned != null) 'lastScanned': lastScanned!.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  TrackedBook copyWith({
    String? bookId,
    String? bookName,
    String? categoryName,
    bool? isBuiltIn,
    String? bookPath,
    BookDetails? bookDetails,
    String? sourceFile,
    DateTime? dateAdded,
    DateTime? lastScanned,
  }) {
    return TrackedBook(
      bookId: bookId ?? this.bookId,
      bookName: bookName ?? this.bookName,
      categoryName: categoryName ?? this.categoryName,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      bookPath: bookPath ?? this.bookPath,
      bookDetails: bookDetails ?? this.bookDetails,
      sourceFile: sourceFile ?? this.sourceFile,
      dateAdded: dateAdded ?? this.dateAdded,
      lastScanned: lastScanned ?? this.lastScanned,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackedBook &&
          runtimeType == other.runtimeType &&
          bookId == other.bookId;

  @override
  int get hashCode => bookId.hashCode;

  @override
  String toString() {
    return 'TrackedBook(bookId: $bookId, bookName: $bookName, '
        'categoryName: $categoryName, isBuiltIn: $isBuiltIn)';
  }
}

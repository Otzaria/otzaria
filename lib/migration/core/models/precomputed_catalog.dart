/// Precomputed catalog tree structure optimized for fast loading.
/// This structure is generated once during database creation and serialized to a binary file.
/// The application loads this file at startup instead of querying the database.
class PrecomputedCatalog {
  final List<CatalogCategory> rootCategories;
  final int version;
  final int totalBooks;
  final int totalCategories;

  const PrecomputedCatalog({
    required this.rootCategories,
    this.version = 1,
    this.totalBooks = 0,
    this.totalCategories = 0,
  });

  factory PrecomputedCatalog.fromJson(Map<String, dynamic> json) {
    return PrecomputedCatalog(
      rootCategories: (json['rootCategories'] as List<dynamic>)
          .map((e) => CatalogCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      version: json['version'] as int? ?? 1,
      totalBooks: json['totalBooks'] as int? ?? 0,
      totalCategories: json['totalCategories'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rootCategories': rootCategories.map((e) => e.toJson()).toList(),
      'version': version,
      'totalBooks': totalBooks,
      'totalCategories': totalCategories,
    };
  }

  PrecomputedCatalog copyWith({
    List<CatalogCategory>? rootCategories,
    int? version,
    int? totalBooks,
    int? totalCategories,
  }) {
    return PrecomputedCatalog(
      rootCategories: rootCategories ?? this.rootCategories,
      version: version ?? this.version,
      totalBooks: totalBooks ?? this.totalBooks,
      totalCategories: totalCategories ?? this.totalCategories,
    );
  }
}

/// Represents a category in the precomputed catalog tree.
/// Contains its books and subcategories in a hierarchical structure.
class CatalogCategory {
  final int id;
  final String title;
  final int level;
  final int? parentId;
  final List<CatalogBook> books;
  final List<CatalogCategory> subcategories;

  const CatalogCategory({
    required this.id,
    required this.title,
    required this.level,
    this.parentId,
    this.books = const [],
    this.subcategories = const [],
  });

  factory CatalogCategory.fromJson(Map<String, dynamic> json) {
    return CatalogCategory(
      id: json['id'] as int,
      title: json['title'] as String,
      level: json['level'] as int,
      parentId: json['parentId'] as int?,
      books: (json['books'] as List<dynamic>?)
              ?.map((e) => CatalogBook.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      subcategories: (json['subcategories'] as List<dynamic>?)
              ?.map((e) => CatalogCategory.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'level': level,
      'parentId': parentId,
      'books': books.map((e) => e.toJson()).toList(),
      'subcategories': subcategories.map((e) => e.toJson()).toList(),
    };
  }

  CatalogCategory copyWith({
    int? id,
    String? title,
    int? level,
    int? parentId,
    List<CatalogBook>? books,
    List<CatalogCategory>? subcategories,
  }) {
    return CatalogCategory(
      id: id ?? this.id,
      title: title ?? this.title,
      level: level ?? this.level,
      parentId: parentId ?? this.parentId,
      books: books ?? this.books,
      subcategories: subcategories ?? this.subcategories,
    );
  }
}

/// Simplified book representation for the catalog tree.
/// Contains only the essential information needed for navigation.
class CatalogBook {
  final int id;
  final String title;
  final int categoryId;
  final double order;
  final List<String> authors;
  final int totalLines;
  final bool isBaseBook;
  final bool hasTargumConnection;
  final bool hasReferenceConnection;
  final bool hasCommentaryConnection;
  final bool hasOtherConnection;

  const CatalogBook({
    required this.id,
    required this.title,
    required this.categoryId,
    this.order = 999.0,
    this.authors = const [],
    this.totalLines = 0,
    this.isBaseBook = false,
    this.hasTargumConnection = false,
    this.hasReferenceConnection = false,
    this.hasCommentaryConnection = false,
    this.hasOtherConnection = false,
  });

  factory CatalogBook.fromJson(Map<String, dynamic> json) {
    return CatalogBook(
      id: json['id'] as int,
      title: json['title'] as String,
      categoryId: json['categoryId'] as int,
      order: (json['order'] as num?)?.toDouble() ?? 999.0,
      authors: (json['authors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      totalLines: json['totalLines'] as int? ?? 0,
      isBaseBook: json['isBaseBook'] as bool? ?? false,
      hasTargumConnection: json['hasTargumConnection'] as bool? ?? false,
      hasReferenceConnection: json['hasReferenceConnection'] as bool? ?? false,
      hasCommentaryConnection:
          json['hasCommentaryConnection'] as bool? ?? false,
      hasOtherConnection: json['hasOtherConnection'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'categoryId': categoryId,
      'order': order,
      'authors': authors,
      'totalLines': totalLines,
      'isBaseBook': isBaseBook,
      'hasTargumConnection': hasTargumConnection,
      'hasReferenceConnection': hasReferenceConnection,
      'hasCommentaryConnection': hasCommentaryConnection,
      'hasOtherConnection': hasOtherConnection,
    };
  }

  CatalogBook copyWith({
    int? id,
    String? title,
    int? categoryId,
    double? order,
    List<String>? authors,
    int? totalLines,
    bool? isBaseBook,
    bool? hasTargumConnection,
    bool? hasReferenceConnection,
    bool? hasCommentaryConnection,
    bool? hasOtherConnection,
  }) {
    return CatalogBook(
      id: id ?? this.id,
      title: title ?? this.title,
      categoryId: categoryId ?? this.categoryId,
      order: order ?? this.order,
      authors: authors ?? this.authors,
      totalLines: totalLines ?? this.totalLines,
      isBaseBook: isBaseBook ?? this.isBaseBook,
      hasTargumConnection: hasTargumConnection ?? this.hasTargumConnection,
      hasReferenceConnection:
          hasReferenceConnection ?? this.hasReferenceConnection,
      hasCommentaryConnection:
          hasCommentaryConnection ?? this.hasCommentaryConnection,
      hasOtherConnection: hasOtherConnection ?? this.hasOtherConnection,
    );
  }
}

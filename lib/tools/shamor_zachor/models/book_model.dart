import '../utils/json_utils.dart';

/// Result of a book search operation
class BookSearchResult {
  final BookDetails bookDetails;
  final String categoryName;
  final BookCategory category;
  final String bookName;
  final String topLevelCategoryName;

  const BookSearchResult(
    this.bookDetails,
    this.categoryName,
    this.category,
    this.bookName,
    this.topLevelCategoryName,
  );
}

/// Represents a category of books (e.g., Tanach, Shas, etc.)
class BookCategory {
  final String name;
  final String contentType;
  final Map<String, BookDetails> books;
  final int defaultStartPage;
  final bool isCustom;
  final String sourceFile;
  final List<BookCategory>? subcategories;
  final String? parentCategoryName;
  final int? schemaVersion;

  const BookCategory({
    required this.name,
    required this.contentType,
    required this.books,
    required this.defaultStartPage,
    required this.isCustom,
    required this.sourceFile,
    this.subcategories,
    this.parentCategoryName,
    this.schemaVersion,
  });

  /// Get all books recursively including subcategories
  Map<String, BookDetails> getAllBooksRecursive() {
    final allBooks = <String, BookDetails>{...books};
    if (subcategories != null) {
      for (final subCategory in subcategories!) {
        allBooks.addAll(subCategory.getAllBooksRecursive());
      }
    }
    return allBooks;
  }
}

/// Hierarchical section generated from a table of contents entry
class BookSection {
  final String id;
  final String title;
  final int level;
  final int startPage;
  final int endPage;
  final List<BookSection> children;

  const BookSection({
    required this.id,
    required this.title,
    required this.level,
    required this.startPage,
    required this.endPage,
    this.children = const [],
  });

  bool get isLeaf => children.isEmpty;

  factory BookSection.fromJson(Map<String, dynamic> json) {
    return BookSection(
      id: JsonUtils.asString(json['id']),
      title: JsonUtils.asString(json['title']),
      level: JsonUtils.asInt(json['level']),
      startPage: JsonUtils.asInt(json['startPage']),
      endPage: JsonUtils.asInt(json['endPage']),
      children: (json['children'] as List<dynamic>? ?? const [])
          .map((child) => BookSection.fromJson(JsonUtils.asMap(child)))
          .toList(),
    );
  }
}

/// Represents a part of a book (e.g., volume, section)
class BookPart {
  final String name;
  final int startPage;
  final int endPage;
  final List<int> excludedPages;
  final List<BookPart> children;
  final int level;
  final String? sectionId;

  const BookPart({
    required this.name,
    required this.startPage,
    required this.endPage,
    this.excludedPages = const [],
    this.children = const [],
    this.level = 1,
    this.sectionId,
  });

  factory BookPart.fromJson(Map<String, dynamic> json) {
    return BookPart(
      name: JsonUtils.asString(json['name']),
      startPage: JsonUtils.asInt(json['start']),
      endPage: JsonUtils.asInt(json['end']),
      excludedPages:
          (json['exclude'] as List<dynamic>?)
              ?.map((e) => JsonUtils.asInt(e))
              .toList() ??
          [],
      children: (json['children'] as List<dynamic>? ?? const [])
          .map((child) => BookPart.fromJson(JsonUtils.asMap(child)))
          .toList(),
      level: JsonUtils.asInt(json['level'] ?? 1),
      sectionId: json['sectionId'] as String?,
    );
  }
}

/// Detailed information about a book
class BookDetails {
  final String contentType;
  final bool isCustom;
  final int? id; // Book ID from database
  final List<BookPart> parts;
  final num? originalPageCount;
  final List<BookSection>? sections;
  final String? categoryPath; // נתיב הקטגוריות המלא מה-DB

  List<LearnableItem>? _learnableItemsCache;
  Map<String, List<int>>? _sectionLeafIndexMapCache;

  BookDetails({
    required this.contentType,
    required this.parts,
    this.isCustom = false,
    this.id,
    this.originalPageCount,
    this.sections,
    this.categoryPath,
  });

  /// Check if this book uses "daf" (page) format
  bool get isDafType => contentType == "דף";

  /// Get all learnable items (cached for performance)
  List<LearnableItem> get learnableItems {
    if (_learnableItemsCache != null) return _learnableItemsCache!;

    if (sections != null && sections!.isNotEmpty) {
      _learnableItemsCache = _buildLearnableItemsFromSections();
      return _learnableItemsCache!;
    }

    final List<LearnableItem> items = [];
    int currentIndex = 0;
    for (final part in parts) {
      for (int i = part.startPage; i <= part.endPage; i++) {
        if (part.excludedPages.contains(i)) {
          continue;
        }

        if (isDafType) {
          items.add(
            LearnableItem(
              partName: part.name,
              pageNumber: i,
              amudKey: 'a',
              absoluteIndex: currentIndex++,
            ),
          );
          items.add(
            LearnableItem(
              partName: part.name,
              pageNumber: i,
              amudKey: 'b',
              absoluteIndex: currentIndex++,
            ),
          );
        } else {
          items.add(
            LearnableItem(
              partName: part.name,
              pageNumber: i,
              amudKey: 'a',
              absoluteIndex: currentIndex++,
            ),
          );
        }
      }
    }
    _learnableItemsCache = items;
    return items;
  }

  /// Get total number of learnable items
  int get totalLearnableItems => learnableItems.length;

  /// Check if this book has multiple parts
  bool get hasMultipleParts =>
      (sections != null && sections!.length > 1) || parts.length > 1;

  bool get hasNestedSections =>
      sections != null && sections!.any((section) => !section.isLeaf);

  Map<String, List<int>> get sectionLeafIndexMap {
    if (_sectionLeafIndexMapCache != null) {
      return _sectionLeafIndexMapCache!;
    }
    if (sections == null || sections!.isEmpty) {
      _sectionLeafIndexMapCache = {};
      return _sectionLeafIndexMapCache!;
    }
    _learnableItemsCache ??= _buildLearnableItemsFromSections();
    return _sectionLeafIndexMapCache ?? {};
  }

  List<LearnableItem> _buildLearnableItemsFromSections() {
    final List<LearnableItem> items = [];
    final Map<String, List<int>> leafMap = {};
    int currentIndex = 0;

    void traverse(BookSection section, List<String> path) {
      final currentPath = [...path, section.title];
      if (section.isLeaf) {
        final learnable = LearnableItem(
          partName: path.isNotEmpty ? path.first : section.title,
          pageNumber: section.startPage,
          amudKey: 'a',
          absoluteIndex: currentIndex,
          sectionId: section.id,
          displayLabel: section.title,
          hierarchyPath: currentPath,
        );
        items.add(learnable);
        leafMap[section.id] = [currentIndex];
        currentIndex++;
      } else {
        final List<int> descendantIndices = [];
        for (final child in section.children) {
          traverse(child, currentPath);
          descendantIndices.addAll(leafMap[child.id] ?? const []);
        }
        if (descendantIndices.isNotEmpty) {
          leafMap[section.id] = descendantIndices;
        }
      }
    }

    for (final section in sections ?? const []) {
      traverse(section, []);
    }

    _sectionLeafIndexMapCache = leafMap;
    return items;
  }
}

/// Represents a learnable item (page, chapter, etc.)
class LearnableItem {
  final String partName;
  final int pageNumber;
  final String amudKey;
  final int absoluteIndex;
  final String? sectionId;
  final String? displayLabel;
  final List<String> hierarchyPath;

  const LearnableItem({
    required this.partName,
    required this.pageNumber,
    required this.amudKey,
    required this.absoluteIndex,
    this.sectionId,
    this.displayLabel,
    this.hierarchyPath = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LearnableItem &&
          runtimeType == other.runtimeType &&
          partName == other.partName &&
          pageNumber == other.pageNumber &&
          amudKey == other.amudKey &&
          absoluteIndex == other.absoluteIndex &&
          sectionId == other.sectionId;

  @override
  int get hashCode =>
      partName.hashCode ^
      pageNumber.hashCode ^
      amudKey.hashCode ^
      absoluteIndex.hashCode ^
      sectionId.hashCode;
}

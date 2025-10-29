import '../utils/json_utils.dart';

/// Result of a book search operation
class BookSearchResult {
  final BookDetails bookDetails;
  final String categoryName;
  final BookCategory category;
  final String bookName;
  final String topLevelCategoryName;

  const BookSearchResult(this.bookDetails, this.categoryName, this.category,
      this.bookName, this.topLevelCategoryName);
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

  factory BookCategory.fromJson(
    Map<String, dynamic> json,
    String sourceFile, {
    bool isCustom = false,
    String? parentCategoryName,
  }) {
    // Check schema version for future migrations
    final schemaVersion = JsonUtils.asInt(json['schemaVersion'] ?? 1);

    Map<String, dynamic> rawData =
        JsonUtils.asMap(json['books'] ?? json['data']);
    Map<String, BookDetails> parsedBooks = {};

    int defaultStartPage =
        JsonUtils.asString(json['content_type']) == "דף" ? 2 : 1;

    rawData.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsedBooks[key] = BookDetails.fromJson(
          value,
          contentType: JsonUtils.asString(json['content_type']),
          isCustom: isCustom,
        );
      }
    });

    List<BookCategory>? subcategories;
    if (json['subcategories'] is List) {
      subcategories = (json['subcategories'] as List)
          .map((subJson) => BookCategory.fromJson(
                JsonUtils.asMap(subJson),
                sourceFile,
                isCustom: isCustom,
                parentCategoryName: JsonUtils.asString(json['name']),
              ))
          .toList();
    }

    return BookCategory(
      name: JsonUtils.asString(json['name']),
      contentType: JsonUtils.asString(json['content_type']),
      books: parsedBooks,
      defaultStartPage: defaultStartPage,
      isCustom: isCustom,
      sourceFile: sourceFile,
      subcategories: subcategories,
      parentCategoryName: parentCategoryName,
      schemaVersion: schemaVersion,
    );
  }

  /// Recursively search for a book by name
  BookSearchResult? findBookRecursive(String bookNameToFind) {
    if (books.containsKey(bookNameToFind)) {
      return BookSearchResult(
          books[bookNameToFind]!, name, this, bookNameToFind, name);
    }
    if (subcategories != null) {
      for (final subCategory in subcategories!) {
        final result = subCategory.findBookRecursive(bookNameToFind);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

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

  BookSection copyWith({
    String? id,
    String? title,
    int? level,
    int? startPage,
    int? endPage,
    List<BookSection>? children,
  }) {
    return BookSection(
      id: id ?? this.id,
      title: title ?? this.title,
      level: level ?? this.level,
      startPage: startPage ?? this.startPage,
      endPage: endPage ?? this.endPage,
      children: children ?? this.children,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'level': level,
        'startPage': startPage,
        'endPage': endPage,
        if (children.isNotEmpty)
          'children': children.map((child) => child.toJson()).toList(),
      };
}

/// Represents a part of a book (e.g., volume, section)
class BookPart {
  final String name;
  final int startPage;
  final int endPage;
  final List<int> excludedPages;
  final bool hasHalfPageAtEnd;
  final List<BookPart> children;
  final int level;
  final String? sectionId;

  const BookPart({
    required this.name,
    required this.startPage,
    required this.endPage,
    this.excludedPages = const [],
    this.hasHalfPageAtEnd = false,
    this.children = const [],
    this.level = 1,
    this.sectionId,
  });

  factory BookPart.fromJson(Map<String, dynamic> json) {
    return BookPart(
      name: JsonUtils.asString(json['name']),
      startPage: JsonUtils.asInt(json['start']),
      endPage: JsonUtils.asInt(json['end']),
      excludedPages: (json['exclude'] as List<dynamic>?)
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

  Map<String, dynamic> toJson() => {
        'name': name,
        'start': startPage,
        'end': endPage,
        if (excludedPages.isNotEmpty) 'exclude': excludedPages,
        if (children.isNotEmpty)
          'children': children.map((child) => child.toJson()).toList(),
        if (level != 1) 'level': level,
        if (sectionId != null) 'sectionId': sectionId,
      };

  factory BookPart.fromSection(BookSection section) {
    return BookPart(
      name: section.title,
      startPage: section.startPage,
      endPage: section.endPage,
      children: section.children.map(BookPart.fromSection).toList(),
      level: section.level,
      sectionId: section.id,
    );
  }
}

/// Detailed information about a book
class BookDetails {
  final String contentType;
  final bool isCustom;
  final String? id;
  final List<BookPart> parts;
  final num? originalPageCount;
  final List<BookSection>? sections;

  List<LearnableItem>? _learnableItemsCache;
  Map<String, List<int>>? _sectionLeafIndexMapCache;
  Map<String, List<String>>? _sectionPathCache;

  BookDetails({
    required this.contentType,
    required this.parts,
    this.isCustom = false,
    this.id,
    this.originalPageCount,
    this.sections,
  });

  factory BookDetails.fromJson(
    Map<String, dynamic> json, {
    required String contentType,
    bool isCustom = false,
    String? id,
  }) {
    List<BookPart> parts = [];
    num? pageCount;
    List<BookSection>? sections;

    if (json['parts'] is List) {
      parts = (json['parts'] as List)
          .map((partJson) => BookPart.fromJson(JsonUtils.asMap(partJson)))
          .toList();
    } else if (json.containsKey('pages')) {
      pageCount = JsonUtils.asNum(json['pages']);
      int startPage =
          JsonUtils.asInt(json['startPage'] ?? (contentType == "דף" ? 2 : 1));

      int endPage;
      bool lastPageIsHalf = false;

      if (contentType == "דף") {
        endPage = startPage + pageCount.ceil() - 1;
        if (pageCount.floor() != pageCount) {
          lastPageIsHalf = true;
        }
      } else {
        endPage = startPage + pageCount.toInt() - 1;
      }

      parts.add(BookPart(
        name: "ראשי",
        startPage: startPage,
        endPage: endPage,
        hasHalfPageAtEnd: lastPageIsHalf,
      ));
    }

    if (json['sections'] is List) {
      sections = (json['sections'] as List)
          .map((raw) => BookSection.fromJson(JsonUtils.asMap(raw)))
          .toList();
    }

    return BookDetails(
      contentType: contentType,
      parts: parts,
      isCustom: isCustom,
      id: id,
      originalPageCount: pageCount,
      sections: sections,
    );
  }

  /// Get the page count for display purposes
  num get pageCountForDisplay {
    if (originalPageCount != null) {
      return originalPageCount!;
    }
    if (parts.isEmpty) return 0;

    // Fallback for older data structures
    return parts
        .map((p) => p.endPage - p.startPage + 1)
        .reduce((a, b) => a + b);
  }

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
          items.add(LearnableItem(
              partName: part.name,
              pageNumber: i,
              amudKey: 'a',
              absoluteIndex: currentIndex++));

          if (!(part.hasHalfPageAtEnd && i == part.endPage)) {
            items.add(LearnableItem(
                partName: part.name,
                pageNumber: i,
                amudKey: 'b',
                absoluteIndex: currentIndex++));
          }
        } else {
          items.add(LearnableItem(
              partName: part.name,
              pageNumber: i,
              amudKey: 'a',
              absoluteIndex: currentIndex++));
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

  /// Clear the learnable items cache (useful for testing)
  void clearCache() {
    _learnableItemsCache = null;
    _sectionLeafIndexMapCache = null;
    _sectionPathCache = null;
  }

  Map<String, dynamic> toJson() => {
        'contentType': contentType,
        'isCustom': isCustom,
        if (id != null) 'id': id,
        'parts': parts.map((p) => p.toJson()).toList(),
        if (originalPageCount != null) 'originalPageCount': originalPageCount,
        if (sections != null)
          'sections': sections!.map((section) => section.toJson()).toList(),
      };

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

  Map<String, List<String>> get sectionPathMap {
    if (_sectionPathCache != null) {
      return _sectionPathCache!;
    }
    if (sections == null || sections!.isEmpty) {
      _sectionPathCache = {};
      return _sectionPathCache!;
    }
    _learnableItemsCache ??= _buildLearnableItemsFromSections();
    return _sectionPathCache ?? {};
  }

  List<LearnableItem> _buildLearnableItemsFromSections() {
    final List<LearnableItem> items = [];
    final Map<String, List<int>> leafMap = {};
    final Map<String, List<String>> pathMap = {};
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
        pathMap[section.id] = currentPath;
        currentIndex++;
      } else {
        final List<int> descendantIndices = [];
        for (final child in section.children) {
          traverse(child, currentPath);
          descendantIndices.addAll(leafMap[child.id] ?? const []);
        }
        if (descendantIndices.isNotEmpty) {
          leafMap[section.id] = descendantIndices;
          pathMap[section.id] = currentPath;
        }
      }
    }

    for (final section in sections ?? const []) {
      traverse(section, []);
    }

    _sectionLeafIndexMapCache = leafMap;
    _sectionPathCache = pathMap;
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

  LearnableItem copyWith({
    String? partName,
    int? pageNumber,
    String? amudKey,
    int? absoluteIndex,
    String? sectionId,
    String? displayLabel,
    List<String>? hierarchyPath,
  }) {
    return LearnableItem(
      partName: partName ?? this.partName,
      pageNumber: pageNumber ?? this.pageNumber,
      amudKey: amudKey ?? this.amudKey,
      absoluteIndex: absoluteIndex ?? this.absoluteIndex,
      sectionId: sectionId ?? this.sectionId,
      displayLabel: displayLabel ?? this.displayLabel,
      hierarchyPath: hierarchyPath ?? this.hierarchyPath,
    );
  }

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
  int get hashCode => partName.hashCode ^
      pageNumber.hashCode ^
      amudKey.hashCode ^
      absoluteIndex.hashCode ^
      sectionId.hashCode;
}

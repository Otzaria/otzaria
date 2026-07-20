import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';

/// עץ הבחירה של היקף החיפוש (קטגוריות → תת-קטגוריות → ספרים) ואלגוריתמי
/// הבחירה שמעליו. לוגיקה טהורה ללא ווידג'טים, משותפת ל-[CategoryTreeSelector]
/// ולתפריט הסינון המאוחד. כל הפעולות מקבלות ומחזירות סט של facets
/// קטגוריאליים בלבד (בלי facets ממדיים — אלה מטופלים בנפרד).
class ScopeTree {
  final List<ScopeNode> rootNodes;
  final Map<String, ScopeNode> nodesByFacet;

  const ScopeTree._(this.rootNodes, this.nodesByFacet);

  factory ScopeTree.fromLibrary(Library library) {
    final nodesByFacet = <String, ScopeNode>{};

    ScopeNode buildCategoryNode(Category category) {
      final sortedCategories = category.subCategories.toList()
        ..sort(
          (a, b) => SearchCatalogueOrderHelper.normalizeOrder(
            a.order,
          ).compareTo(SearchCatalogueOrderHelper.normalizeOrder(b.order)),
        );
      final sortedBooks = category.books.toList()
        ..sort(
          (a, b) => SearchCatalogueOrderHelper.normalizeOrder(
            a.order,
          ).compareTo(SearchCatalogueOrderHelper.normalizeOrder(b.order)),
        );

      final children = <ScopeNode>[
        for (final subCategory in sortedCategories)
          buildCategoryNode(subCategory),
        for (final book in sortedBooks)
          BookScopeNode(
            book: book,
            facet: FacetHelper.buildBookFacet(
              FacetHelper.resolveCategoryPath(book),
              book,
            ),
          ),
      ];

      final node = CategoryScopeNode(category: category, children: children);
      nodesByFacet[node.facet] = node;
      for (final child in children) {
        nodesByFacet[child.facet] = child;
      }
      return node;
    }

    // התיקיות העליונות בסדר מסך הספרייה (topCategoryOrder), בדיוק כמו
    // library_browser; הרמות הפנימיות ממויינות לפי normalizeOrder.
    final sortedTop = library.subCategories.toList()
      ..sort(
        (a, b) => SearchCatalogueOrderHelper.topCategoryOrder(
          a,
        ).compareTo(SearchCatalogueOrderHelper.topCategoryOrder(b)),
      );
    final rootNodes = [
      for (final category in sortedTop) buildCategoryNode(category),
    ];
    return ScopeTree._(rootNodes, nodesByFacet);
  }

  // --- שאילתות מצב ---

  bool isAllSelected(Set<String> selection) => selection.contains('/');

  /// מחזיר true/false/null (tristate) למצב הסימון של קטגוריה לפי נתיבה.
  bool? categoryCheckState(String categoryPath, Set<String> selection) {
    if (isAllSelected(selection)) return true;
    if (selection.contains(categoryPath)) return true;
    for (final facet in selection) {
      if (facet != '/' && categoryPath.startsWith('$facet/')) return true;
    }
    if (_hasSelectedDescendant(categoryPath, selection)) return null;
    return false;
  }

  bool _hasSelectedDescendant(String categoryPath, Set<String> selection) {
    for (final facet in selection) {
      if (facet.startsWith('$categoryPath/')) return true;
    }
    return false;
  }

  /// האם [facet] מכוסה ע"י הבחירה (נבחר ישירות, או אב שלו נבחר, או הכל).
  bool isFacetCovered(String facet, Set<String> selection) {
    if (isAllSelected(selection)) return true;
    if (selection.contains(facet)) return true;
    for (final selected in selection) {
      if (selected == '/' || selected == facet) continue;
      if (facet.startsWith('$selected/')) return true;
    }
    return false;
  }

  // --- בחירה ---

  Set<String> selectFacet(String facet, Set<String> selection) {
    selection.remove('/');

    for (final selected in selection.toList()) {
      if (facet == selected || facet.startsWith('$selected/')) {
        selection.remove(selected);
      }
    }

    for (final selected in selection.toList()) {
      if (selected.startsWith('$facet/')) {
        selection.remove(selected);
      }
    }

    selection.add(facet);
    return _consolidateSelection(selection);
  }

  Set<String> deselectFacet(String facet, Set<String> selection) {
    if (selection.remove(facet)) {
      return _consolidateSelection(selection);
    }

    final coveringFacet = _findCoveringFacet(facet, selection);
    if (coveringFacet == null) {
      return selection;
    }

    final excludedNode = nodesByFacet[facet];
    if (excludedNode == null) {
      selection.remove(coveringFacet);
      return _consolidateSelection(selection);
    }

    if (coveringFacet == '/') {
      _explodeExcludingNode(excludedNode, selection, rootNodes, '/');
      return _consolidateSelection(selection);
    }

    final coveringNode = nodesByFacet[coveringFacet];
    if (coveringNode == null) {
      selection.remove(coveringFacet);
      return _consolidateSelection(selection);
    }

    _explodeExcludingNode(
      excludedNode,
      selection,
      coveringNode.children,
      coveringFacet,
    );
    return _consolidateSelection(selection);
  }

  String? _findCoveringFacet(String facet, Set<String> selection) {
    String? bestMatch;
    for (final selected in selection) {
      if (selected == '/') {
        bestMatch = '/';
        continue;
      }
      if (facet.startsWith('$selected/')) {
        if (bestMatch == null || selected.length > bestMatch.length) {
          bestMatch = selected;
        }
      }
    }
    return bestMatch;
  }

  void _explodeExcludingNode(
    ScopeNode excludedNode,
    Set<String> selection,
    List<ScopeNode> siblings,
    String coveringFacet,
  ) {
    selection.remove(coveringFacet);

    for (final child in siblings) {
      if (child.facet == excludedNode.facet) {
        continue;
      }
      if (_isAncestorFacet(child.facet, excludedNode.facet)) {
        _explodeExcludingNode(
          excludedNode,
          selection,
          child.children,
          child.facet,
        );
      } else {
        selection.add(child.facet);
      }
    }
  }

  bool _isAncestorFacet(String ancestor, String facet) {
    return facet == ancestor || facet.startsWith('$ancestor/');
  }

  Set<String> _consolidateSelection(Set<String> selection) {
    if (selection.contains('/')) {
      return {'/'};
    }

    final result = Set<String>.from(selection);
    final allCovered =
        rootNodes.isNotEmpty &&
        rootNodes.every((node) => _consolidateNode(node, result));

    if (allCovered) {
      return {'/'};
    }

    return result;
  }

  bool _consolidateNode(ScopeNode node, Set<String> selection) {
    if (selection.contains(node.facet)) {
      return true;
    }

    for (final selected in selection) {
      if (selected != '/' && node.facet.startsWith('$selected/')) {
        return true;
      }
    }

    if (node.children.isEmpty) {
      return false;
    }

    final allChildrenCovered = node.children.every(
      (child) => _consolidateNode(child, selection),
    );
    if (!allChildrenCovered) {
      return false;
    }

    for (final child in node.children) {
      selection.remove(child.facet);
      _removeNodeDescendants(child, selection);
    }
    selection.add(node.facet);
    return true;
  }

  void _removeNodeDescendants(ScopeNode node, Set<String> selection) {
    for (final child in node.children) {
      selection.remove(child.facet);
      _removeNodeDescendants(child, selection);
    }
  }

  // --- חיפוש שטוח בעץ ---

  List<ScopeSearchResultItem> search(String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final results = <ScopeSearchResultItem>[];

    void visit(ScopeNode node) {
      final normalizedTitle = normalizeFindText(node.title);
      final normalizedSubtitle = normalizeFindText(node.subtitle);
      final matches = findNormalizedTextMatches(
        normalizedQuery: normalizedQuery,
        normalizedPrimaryText: normalizedTitle,
        normalizedSecondaryText: normalizedSubtitle,
      );

      if (matches) {
        results.add(
          ScopeSearchResultItem(
            facet: node.facet,
            title: node.title,
            subtitle: node.subtitle,
            isBook: node.isBook,
            score: findNormalizedTextMatchRank(
              normalizedQuery: normalizedQuery,
              normalizedPrimaryText: normalizedTitle,
              normalizedSecondaryText: normalizedSubtitle,
            ),
            lengthDelta: findNormalizedTextMatchLengthDelta(
              normalizedQuery: normalizedQuery,
              normalizedPrimaryText: normalizedTitle,
              normalizedSecondaryText: normalizedSubtitle,
            ),
          ),
        );
      }

      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in rootNodes) {
      visit(node);
    }

    results.sort((a, b) {
      final scoreCompare = a.score.compareTo(b.score);
      if (scoreCompare != 0) return scoreCompare;
      final lengthDeltaCompare = a.lengthDelta.compareTo(b.lengthDelta);
      if (lengthDeltaCompare != 0) return lengthDeltaCompare;
      if (a.isBook != b.isBook) return a.isBook ? 1 : -1;
      return a.title.compareTo(b.title);
    });

    return results;
  }

  /// כל צמתי הספרים בעץ — לשיטוט/סינון לפי מאפייני ספר (למשל ספרי יסוד).
  List<BookScopeNode> allBookNodes() {
    final books = <BookScopeNode>[];
    void visit(ScopeNode node) {
      if (node is BookScopeNode) books.add(node);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in rootNodes) {
      visit(node);
    }
    return books;
  }

  // --- ניווט אקורדיון (ילדים גלויים + קיפול שרשרת יחיד) ---

  /// האם תחת [node] יש ספר מותר (או שהוא עצמו ספר כזה). [onlyBooks] = facets
  /// של ספרים מותרים (למשל ספרי יסוד); null = הכול מותר.
  bool _containsAllowedBook(ScopeNode node, Set<String>? onlyBooks) {
    if (onlyBooks == null) return true;
    if (node.isBook) return onlyBooks.contains(node.facet);
    for (final child in node.children) {
      if (_containsAllowedBook(child, onlyBooks)) return true;
    }
    return false;
  }

  /// הילדים הגלויים של [parent] (או השורש כש-null) בסדר הספרייה, לאחר סינון
  /// לפי [onlyBooks].
  List<ScopeNode> visibleChildren(ScopeNode? parent, {Set<String>? onlyBooks}) {
    final children = parent == null ? rootNodes : parent.children;
    if (onlyBooks == null) return children;
    return [
      for (final child in children)
        if (_containsAllowedBook(child, onlyBooks)) child,
    ];
  }

  /// אם [folder] מתקפל לספר בודד — שרשרת של "ילד יחיד" שמסתיימת בספר אחד.
  BookScopeNode? singleBookOf(ScopeNode folder, {Set<String>? onlyBooks}) {
    var current = folder;
    while (true) {
      final kids = visibleChildren(current, onlyBooks: onlyBooks);
      if (kids.length != 1) return null;
      final only = kids.first;
      if (only is BookScopeNode) return only;
      current = only;
    }
  }

  /// הצמתים להצגה בעת הרחבת [folder] — יורד בשרשרת תת-תיקיה-יחידה כדי
  /// שהתיקיה הראשית תיפתח ישירות לתוכן המשמעותי.
  List<ScopeNode> expandedChildren(ScopeNode folder, {Set<String>? onlyBooks}) {
    var current = folder;
    while (true) {
      final kids = visibleChildren(current, onlyBooks: onlyBooks);
      if (kids.length == 1 && !kids.first.isBook) {
        current = kids.first;
        continue;
      }
      return kids;
    }
  }
}

abstract class ScopeNode {
  final String facet;
  final String title;
  final String subtitle;
  final List<ScopeNode> children;

  const ScopeNode({
    required this.facet,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  bool get isBook;
}

class CategoryScopeNode extends ScopeNode {
  CategoryScopeNode({required Category category, required super.children})
    : super(
        facet: category.path,
        title: category.title,
        subtitle: category.path == '/' ? '' : category.path.substring(1),
      );

  @override
  bool get isBook => false;
}

class BookScopeNode extends ScopeNode {
  final Book book;

  BookScopeNode({required this.book, required super.facet})
    : super(
        title: book.title,
        subtitle: [
          if ((FacetHelper.resolveCategoryPath(book) ?? '').isNotEmpty)
            (FacetHelper.resolveCategoryPath(book) ?? '').replaceFirst('/', ''),
          if ((book.author ?? '').trim().isNotEmpty) book.author!.trim(),
        ].join(' • '),
        children: const [],
      );

  @override
  bool get isBook => true;
}

class ScopeSearchResultItem {
  final String facet;
  final String title;
  final String subtitle;
  final bool isBook;
  final int score;
  final int lengthDelta;

  const ScopeSearchResultItem({
    required this.facet,
    required this.title,
    required this.subtitle,
    required this.isBook,
    required this.score,
    required this.lengthDelta,
  });
}

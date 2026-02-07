/// Book metadata from the JSON file, used during the database generation process.
class BookMetadata {
  /// The title of the book.
  final String title;

  /// The full description of the book.
  final String? description;

  /// A short description of the book.
  final String? shortDescription;

  /// The author of the book.
  final String? author;

  /// Alternative titles for the book.
  final List<String>? extraTitles;

  /// A short description in Hebrew.
  final String? heShortDesc;

  /// The publication date of the book.
  final String? pubDate;

  /// The publication place of the book.
  final String? pubPlace;

  /// The display order of the book within its category.
  final double? order;

  const BookMetadata({
    required this.title,
    this.description,
    this.shortDescription,
    this.author,
    this.extraTitles,
    this.heShortDesc,
    this.pubDate,
    this.pubPlace,
    this.order,
  });

  factory BookMetadata.fromJson(Map<String, dynamic> json) =>
      BookMetadata.fromMap(json);

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'shortDescription': shortDescription,
        'author': author,
        'extraTitles': extraTitles,
        'heShortDesc': heShortDesc,
        'pubDate': pubDate,
        'pubPlace': pubPlace,
        'order': order,
      };

  /// Creates a BookMetadata instance from a map (e.g., from JSON).
  factory BookMetadata.fromMap(Map<String, dynamic> map) {
    return BookMetadata(
      title: map['title'] as String,
      description: map['description'] as String?,
      shortDescription: map['shortDescription'] as String?,
      author: map['author'] as String?,
      extraTitles: map['extraTitles'] != null
          ? List<String>.from(map['extraTitles'])
          : null,
      heShortDesc: map['heShortDesc'] as String?,
      pubDate: map['pubDate'] as String?,
      pubPlace: map['pubPlace'] as String?,
      order: (map['order'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() {
    return 'BookMetadata(title: $title, author: $author)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BookMetadata &&
        other.title == title &&
        other.description == description &&
        other.shortDescription == shortDescription &&
        other.author == author &&
        other.heShortDesc == heShortDesc &&
        other.pubDate == pubDate &&
        other.pubPlace == pubPlace &&
        other.order == order;
  }

  @override
  int get hashCode {
    return title.hashCode ^
        description.hashCode ^
        shortDescription.hashCode ^
        author.hashCode ^
        heShortDesc.hashCode ^
        pubDate.hashCode ^
        pubPlace.hashCode ^
        order.hashCode;
  }
}

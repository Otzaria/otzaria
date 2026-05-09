import 'package:collection/collection.dart';
import 'types_helper.dart';

import 'author.dart';
import 'pub_date.dart';
import 'pub_place.dart';
import 'topic.dart';

/// Represents a book in the library
class Book {
  /// The unique identifier of the book
  final int id;

  /// The identifier of the category this book belongs to
  final int categoryId;

  /// The identifier of the source this book originates from
  final int sourceId;

  /// The title of the book
  final String title;

  /// The list of authors of this book
  final List<Author> authors;

  /// The list of topics associated with this book
  final List<Topic> topics;

  /// The list of publication places for this book
  final List<PubPlace> pubPlaces;

  /// The list of publication dates for this book
  final List<PubDate> pubDates;

  /// A short description of the book in Hebrew
  final String? heShortDesc;

  /// The display order of the book within its category
  final double order;

  /// The total number of lines in the book
  final int totalLines;

  final bool isBaseBook;
  final bool hasTargumConnection;
  final bool hasReferenceConnection;
  final bool hasSourceConnection;
  final bool hasCommentaryConnection;
  final bool hasOtherConnection;
  final bool hasAltStructures;
  final bool hasTeamim;
  final bool hasNekudot;

  /// Whether this book's content is stored externally (not in DB lines table)
  final bool isContentExternal;

  /// External library ID (e.g., Sefaria ref) for books from external sources
  final String? externalLibraryId;

  /// Whether this is a personal/user-added book
  final bool isPersonal;

  /// File path for external content books
  final String? filePath;

  /// File type (txt, pdf, epub, etc.)
  final String? fileType;

  /// File size in bytes
  final int? fileSize;

  /// Last modified timestamp (milliseconds since epoch)
  final int? lastModified;

  /// Number of pages (optional, mostly for PDF)
  final int? pages;

  /// Volume label/number (optional)
  final String? volume;

  const Book({
    this.id = 0,
    required this.categoryId,
    required this.sourceId,
    required this.title,
    this.authors = const [],
    this.topics = const [],
    this.pubPlaces = const [],
    this.pubDates = const [],
    this.heShortDesc,
    this.order = 999.0,
    this.totalLines = 0,
    this.isBaseBook = false,
    this.hasTargumConnection = false,
    this.hasReferenceConnection = false,
    this.hasSourceConnection = false,
    this.hasCommentaryConnection = false,
    this.hasOtherConnection = false,
    this.hasAltStructures = false,
    this.hasTeamim = false,
    this.hasNekudot = false,
    this.isContentExternal = false,
    this.externalLibraryId,
    this.isPersonal = false,
    this.filePath,
    this.fileType,
    this.fileSize,
    this.lastModified,
    this.pages,
    this.volume,
  });

  /// מחזיר האם תוכן הספר נטען מקובץ חיצוני במערכת הקבצים.
  bool get isFileBacked {
    final normalizedPath = filePath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) {
      return false;
    }

    final normalizedType = (fileType ?? 'txt').toLowerCase();
    return normalizedType != 'link' && normalizedType != 'url';
  }

  Book copyWith({
    int? id,
    int? categoryId,
    int? sourceId,
    String? title,
    List<Author>? authors,
    List<Topic>? topics,
    List<PubPlace>? pubPlaces,
    List<PubDate>? pubDates,
    String? heShortDesc,
    double? order,
    int? totalLines,
    bool? isBaseBook,
    bool? hasTargumConnection,
    bool? hasReferenceConnection,
    bool? hasSourceConnection,
    bool? hasCommentaryConnection,
    bool? hasOtherConnection,
    bool? hasAltStructures,
    bool? hasTeamim,
    bool? hasNekudot,
    bool? isContentExternal,
    String? externalLibraryId,
    bool? isPersonal,
    String? filePath,
    String? fileType,
    int? fileSize,
    int? lastModified,
    int? pages,
    String? volume,
  }) {
    return Book(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      topics: topics ?? this.topics,
      pubPlaces: pubPlaces ?? this.pubPlaces,
      pubDates: pubDates ?? this.pubDates,
      heShortDesc: heShortDesc ?? this.heShortDesc,
      order: order ?? this.order,
      totalLines: totalLines ?? this.totalLines,
      isBaseBook: isBaseBook ?? this.isBaseBook,
      hasTargumConnection: hasTargumConnection ?? this.hasTargumConnection,
      hasReferenceConnection:
          hasReferenceConnection ?? this.hasReferenceConnection,
      hasSourceConnection: hasSourceConnection ?? this.hasSourceConnection,
      hasCommentaryConnection:
          hasCommentaryConnection ?? this.hasCommentaryConnection,
      hasOtherConnection: hasOtherConnection ?? this.hasOtherConnection,
      hasAltStructures: hasAltStructures ?? this.hasAltStructures,
      hasTeamim: hasTeamim ?? this.hasTeamim,
      hasNekudot: hasNekudot ?? this.hasNekudot,
      isContentExternal: isContentExternal ?? this.isContentExternal,
      externalLibraryId: externalLibraryId ?? this.externalLibraryId,
      isPersonal: isPersonal ?? this.isPersonal,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      lastModified: lastModified ?? this.lastModified,
      pages: pages ?? this.pages,
      volume: volume ?? this.volume,
    );
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as int? ?? 0,
      categoryId: json['categoryId'] as int,
      sourceId: json['sourceId'] as int,
      title: json['title'] as String,
      authors: (json['authors'] as List<dynamic>?)
              ?.map((e) => Author.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      topics: (json['topics'] as List<dynamic>?)
              ?.map((e) => Topic.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pubPlaces: (json['pubPlaces'] as List<dynamic>?)
              ?.map((e) => PubPlace.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pubDates: (json['pubDates'] as List<dynamic>?)
              ?.map((e) => PubDate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      heShortDesc: json['heShortDesc'] as String?,
      order: (json['orderIndex'] as num?)?.toDouble() ??
          (json['order'] as num?)?.toDouble() ??
          999.0,
      totalLines: json['totalLines'] as int? ?? 0,
      isBaseBook: safeBoolFromJson(json['isBaseBook'], false),
      hasTargumConnection: safeBoolFromJson(json['hasTargumConnection'], false),
      hasReferenceConnection:
          safeBoolFromJson(json['hasReferenceConnection'], false),
      hasSourceConnection: safeBoolFromJson(json['hasSourceConnection'], false),
      hasCommentaryConnection:
          safeBoolFromJson(json['hasCommentaryConnection'], false),
      hasOtherConnection: safeBoolFromJson(json['hasOtherConnection'], false),
      hasAltStructures: safeBoolFromJson(json['hasAltStructures'], false),
      hasTeamim: safeBoolFromJson(json['hasTeamim'], false),
      hasNekudot: safeBoolFromJson(json['hasNekudot'], false),
      isContentExternal: safeBoolFromJson(json['isContentExternal'], false),
      externalLibraryId: json['externalLibraryId'] as String?,
      isPersonal: safeBoolFromJson(json['isPersonal'], false),
      filePath: json['filePath'] as String?,
      fileType: json['fileType'] as String?,
      fileSize: json['fileSize'] as int?,
      lastModified: json['lastModified'] as int?,
      pages: json['pages'] as int?,
      volume: json['volume'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'sourceId': sourceId,
      'title': title,
      'authors': authors.map((e) => e.toJson()).toList(),
      'topics': topics.map((e) => e.toJson()).toList(),
      'pubPlaces': pubPlaces.map((e) => e.toJson()).toList(),
      'pubDates': pubDates.map((e) => e.toJson()).toList(),
      'heShortDesc': heShortDesc,
      'orderIndex': order,
      'order': order,
      'totalLines': totalLines,
      'isBaseBook': isBaseBook,
      'hasTargumConnection': hasTargumConnection,
      'hasReferenceConnection': hasReferenceConnection,
      'hasSourceConnection': hasSourceConnection,
      'hasCommentaryConnection': hasCommentaryConnection,
      'hasOtherConnection': hasOtherConnection,
      'hasAltStructures': hasAltStructures,
      'hasTeamim': hasTeamim,
      'hasNekudot': hasNekudot,
      'isContentExternal': isContentExternal,
      'externalLibraryId': externalLibraryId,
      'isPersonal': isPersonal,
      'filePath': filePath,
      'fileType': fileType,
      'fileSize': fileSize,
      'lastModified': lastModified,
      'pages': pages,
      'volume': volume,
    };
  }

  @override
  String toString() =>
      'Book(id: $id, title: $title, isContentExternal: $isContentExternal, isPersonal: $isPersonal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          categoryId == other.categoryId &&
          sourceId == other.sourceId &&
          title == other.title &&
          const ListEquality().equals(authors, other.authors) &&
          const ListEquality().equals(topics, other.topics) &&
          const ListEquality().equals(pubPlaces, other.pubPlaces) &&
          const ListEquality().equals(pubDates, other.pubDates) &&
          heShortDesc == other.heShortDesc &&
          order == other.order &&
          totalLines == other.totalLines &&
          isBaseBook == other.isBaseBook &&
          hasTargumConnection == other.hasTargumConnection &&
          hasReferenceConnection == other.hasReferenceConnection &&
          hasSourceConnection == other.hasSourceConnection &&
          hasCommentaryConnection == other.hasCommentaryConnection &&
          hasOtherConnection == other.hasOtherConnection &&
          hasAltStructures == other.hasAltStructures &&
          hasTeamim == other.hasTeamim &&
          hasNekudot == other.hasNekudot &&
          isContentExternal == other.isContentExternal &&
          externalLibraryId == other.externalLibraryId &&
          isPersonal == other.isPersonal &&
          filePath == other.filePath &&
          fileType == other.fileType &&
          fileSize == other.fileSize &&
          lastModified == other.lastModified &&
          pages == other.pages &&
          volume == other.volume;

  @override
  int get hashCode =>
      id.hashCode ^
      categoryId.hashCode ^
      sourceId.hashCode ^
      title.hashCode ^
      const ListEquality().hash(authors) ^
      const ListEquality().hash(topics) ^
      const ListEquality().hash(pubPlaces) ^
      const ListEquality().hash(pubDates) ^
      heShortDesc.hashCode ^
      order.hashCode ^
      totalLines.hashCode ^
      isBaseBook.hashCode ^
      hasTargumConnection.hashCode ^
      hasReferenceConnection.hashCode ^
      hasSourceConnection.hashCode ^
      hasCommentaryConnection.hashCode ^
      hasOtherConnection.hashCode ^
      hasAltStructures.hashCode ^
      hasTeamim.hashCode ^
      hasNekudot.hashCode ^
      isContentExternal.hashCode ^
      externalLibraryId.hashCode ^
      isPersonal.hashCode ^
      filePath.hashCode ^
      fileType.hashCode ^
      fileSize.hashCode ^
      lastModified.hashCode ^
      pages.hashCode ^
      volume.hashCode;
}

import 'package:equatable/equatable.dart';
import 'package:otzaria/models/book_source.dart';

class AltTocStructure extends Equatable {
  final int id;
  final int bookId;
  final String key;
  final String? title;
  final String? heTitle;

  /// המסד שממנו נקרא המבנה — מרחבי המזהים של המסדים נפרדים.
  final BookSource source;

  bool get isUserBook => source.isUser;

  const AltTocStructure({
    required this.id,
    required this.bookId,
    required this.key,
    this.title,
    this.heTitle,
    this.source = BookSource.official,
  });

  factory AltTocStructure.fromJson(Map<String, dynamic> json) {
    return AltTocStructure(
      id: json['id'] as int,
      bookId: json['bookId'] as int,
      key: json['key'] as String,
      title: json['title'] as String?,
      heTitle: json['heTitle'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'key': key,
      'title': title,
      'heTitle': heTitle,
    };
  }

  @override
  List<Object?> get props => [id, bookId, key, title, heTitle, source];
}

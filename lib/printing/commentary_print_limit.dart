import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/models/links.dart';

/// מגביל שורות מקור לכל ספר יעד לאורך עבודת הדפסה אחת.
class CommentaryPrintLimit {
  CommentaryPrintLimit({
    Future<BookProtection> Function(Link)? protectionResolver,
  }) : _protectionOf =
           protectionResolver ?? BookProtectionRepository.instance.forLink;

  final Future<BookProtection> Function(Link) _protectionOf;
  final _protectionByBook = <String, BookProtection>{};
  final _usedByBook = <String, int>{};

  Future<Link?> take(Link link) async {
    final key = link.targetIdentityKey;
    final protection = _protectionByBook[key] ??= await _protectionOf(link);
    final limit = protection.maxPrintSegments;
    if (limit == null) return link;
    final remaining = limit - (_usedByBook[key] ?? 0);
    if (remaining <= 0) return null;
    final count = linkSegmentCount(link).clamp(0, remaining);
    _usedByBook[key] = (_usedByBook[key] ?? 0) + count;
    return count == linkSegmentCount(link)
        ? link
        : link.withTargetRange(link.index2, link.index2 + count - 1);
  }
}

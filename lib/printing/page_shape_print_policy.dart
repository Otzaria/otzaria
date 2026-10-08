import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_plugin_api.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show getTitleFromPath;

/// תוכן צורת הדף מוגבל לפי ספרי היעד המוצגים; צילום זמין רק בלי מכסת שורות.
Future<
  ({List<String> commentators, BookProtection protection, bool useScreenshot})
>
resolvePageShapePrintPolicy({
  required BookProtection mainProtection,
  required PageShapeLayoutSnapshot? layout,
  required List<String> availableCommentators,
  required List<Link> links,
  Future<BookProtection> Function(Link)? protectionResolver,
  Future<BookProtection> Function(String)? titleProtectionResolver,
}) async {
  final commentators = layout == null
      ? availableCommentators
      : [
          for (final entry in [
            layout.left,
            ...layout.right,
            layout.bottom,
            layout.bottomRight,
          ])
            if (entry != null && entry.visible) entry.commentator,
        ];
  final selectedTitles = commentators.toSet();
  final matchedTitles = <String>{};
  final seenTargets = <String>{};
  final repository = BookProtectionRepository.instance;
  final protectionOf = protectionResolver ?? repository.forLink;
  final protectionOfTitle =
      titleProtectionResolver ?? (title) => repository.forTitle(title);
  var protection = mainProtection;
  for (final link in links) {
    final title = getTitleFromPath(link.path2);
    if (!selectedTitles.contains(title)) continue;
    matchedTitles.add(title);
    if (!seenTargets.add(link.targetIdentityKey)) continue;
    protection = protection.strictest(await protectionOf(link));
  }
  for (final title in selectedTitles.difference(matchedTitles)) {
    protection = protection.strictest(await protectionOfTitle(title));
  }
  return (
    commentators: commentators,
    protection: protection,
    useScreenshot: layout != null && protection.maxPrintSegments == null,
  );
}

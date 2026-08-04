import 'dart:isolate';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

List<Link> mergeLinksByIdentity(
  List<Link> existing,
  List<Link> incoming,
) {
  final merged = <String, Link>{
    for (final link in existing) _linkIdentityKey(link): link,
  };

  for (final link in incoming) {
    final key = _linkIdentityKey(link);
    final existingLink = merged[key];
    if (existingLink == null ||
        link.baseProvenance >= existingLink.baseProvenance) {
      merged[key] = link;
    }
  }

  final links = merged.values.toList();
  links.sort((a, b) {
    final indexCompare = a.index1.compareTo(b.index1);
    if (indexCompare != 0) return indexCompare;

    final pathCompare = a.path2.compareTo(b.path2);
    if (pathCompare != 0) return pathCompare;

    final targetCompare = a.index2.compareTo(b.index2);
    if (targetCompare != 0) return targetCompare;

    return a.connectionType.compareTo(b.connectionType);
  });

  return links;
}

String _linkIdentityKey(Link link) {
  return '${link.index1}|${link.path2}|${link.index2}|${link.connectionType}|${link.start}|${link.end}';
}

Map<int, List<Link>> buildLinksByLineMap(List<Link> links) {
  final linksByLine = <int, List<Link>>{};
  for (final link in links) {
    final list = linksByLine[link.index1];
    if (list == null) {
      linksByLine[link.index1] = [link];
    } else {
      list.add(link);
    }
  }
  return linksByLine;
}

List<Link> computeVisibleLinks({
  required List<Link> links,
  required List<int> visibleIndices,
  required Set<int> selectedIndices,
  required Map<int, List<Link>> linksByLine,
}) {
  final targetIndices = selectedIndices.isNotEmpty
      ? selectedIndices
      : visibleIndices;

  final visibleLinks = <Link>[];

  for (final index in targetIndices) {
    final candidates = linksByLine[index + 1] ?? const [];

    for (final link in candidates) {
      if (!LinkTypes.isDependentTextLink(link.connectionType) &&
          link.start == null &&
          link.end == null) {
        visibleLinks.add(link);
      }
    }
  }

  final titles = <Link, String>{};
  final pathCache = <String, String>{};
  for (final link in visibleLinks) {
    titles[link] = pathCache.putIfAbsent(
      link.path2,
      () => utils.getTitleFromPath(link.path2),
    );
  }
  visibleLinks.sort((a, b) => titles[a]!.compareTo(titles[b]!));

  return visibleLinks;
}

Future<
  ({
    List<Link> links,
    Map<int, List<Link>> linksByLine,
    List<Link> visibleLinks,
  })
>
processLinksForState({
  required List<Link> existingLinks,
  required List<Link> incomingLinks,
  required bool replaceExisting,
  required List<int> visibleIndices,
  required Set<int> selectedIndices,
}) async {
  const asyncProcessingThreshold = 250;
  final estimatedLinkCount =
      (replaceExisting ? 0 : existingLinks.length) + incomingLinks.length;

  if (estimatedLinkCount <= asyncProcessingThreshold) {
    final links = mergeLinksByIdentity(
      replaceExisting ? const [] : existingLinks,
      incomingLinks,
    );
    final linksByLine = buildLinksByLineMap(links);
    final visibleLinks = computeVisibleLinks(
      links: links,
      visibleIndices: visibleIndices,
      selectedIndices: selectedIndices,
      linksByLine: linksByLine,
    );
    return (
      links: links,
      linksByLine: linksByLine,
      visibleLinks: visibleLinks,
    );
  }

  return Isolate.run(() {
    final links = mergeLinksByIdentity(
      replaceExisting ? const [] : existingLinks,
      incomingLinks,
    );
    final linksByLine = buildLinksByLineMap(links);
    final visibleLinks = computeVisibleLinks(
      links: links,
      visibleIndices: visibleIndices,
      selectedIndices: selectedIndices,
      linksByLine: linksByLine,
    );
    return (
      links: links,
      linksByLine: linksByLine,
      visibleLinks: visibleLinks,
    );
  });
}

List<String> buildPreviewLines(String previewContent, int previewStartLine) {
  final previewLines = previewContent.split('\n');
  if (previewStartLine <= 0) {
    return previewLines;
  }

  return List<String>.filled(previewStartLine, '', growable: true)
    ..addAll(previewLines);
}

Future<List<String>> splitContentLines(String content) async {
  if (content.isEmpty) {
    return const [];
  }

  return Isolate.run(() => content.split('\n'));
}

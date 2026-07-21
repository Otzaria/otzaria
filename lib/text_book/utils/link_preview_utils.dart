import 'dart:async';

import 'package:otzaria/models/links.dart';

/// האם כתובת זו תומכת בחלונית תצוגה מקדימה בריחוף.
bool isPreviewHoverableUrl(String url) =>
    url.startsWith('otzaria://anchor') ||
    url.startsWith('otzaria://inline-link') ||
    url.startsWith('otzaria://book-note') ||
    url.startsWith('otzaria://note');

/// בונה קישור לתצוגה מקדימה מכתובת של קישור־טווח (`start/end`).
Link? inlineLinkFromPreviewUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'otzaria' || uri?.host != 'inline-link') return null;
  final path = uri!.queryParameters['path'];
  final index = int.tryParse(uri.queryParameters['index'] ?? '');
  if (path == null || path.isEmpty || index == null || index <= 0) return null;
  return Link(
    heRef: uri.queryParameters['ref'] ?? '',
    index1: 0,
    path2: path,
    index2: index,
    connectionType: 'reference',
  );
}

/// מתחיל לטעון את תוכן וכתובת היעד בזמן השהיית הריחוף.
void prefetchLinkPreview(Link link) {
  unawaited(link.content.then<void>((_) {}, onError: (_, _) {}));
  unawaited(link.displayReference.then<void>((_) {}, onError: (_, _) {}));
}

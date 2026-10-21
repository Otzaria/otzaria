import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// הערה עשירה של התוסף הישן כ-Quill Delta; תגית לא מוכרת נפרמת לטקסט שבה,
/// וקישור נשמר רק ב-http/https. null להערה בלי טקסט.
String? legacyNoteHtmlToDelta(String html) {
  final fragment = html_parser.parseFragment(
    html.length > _maxHtmlLength ? html.substring(0, _maxHtmlLength) : html,
  );
  final builder = _DeltaBuilder();
  builder.visitChildren(fragment, const {}, depth: 0);
  return builder.build();
}

/// הטקסט הפשוט של Delta, למקרה שהתוסף לא שמר עותק פשוט של ההערה.
String legacyDeltaPlainText(String delta) {
  final ops = jsonDecode(delta) as List<dynamic>;
  return [
    for (final op in ops)
      if (op is Map && op['insert'] is String) op['insert'] as String,
  ].join().trim();
}

const int _maxHtmlLength = 20000;
const int _maxDepth = 40;
const String _markColor = '#fff59d';

const Map<String, double> _fontSizes = {
  'xx-small': 12,
  'x-small': 12,
  'small': 14,
  'large': 20,
  'x-large': 24,
  'xx-large': 28,
};

final RegExp _safeHref = RegExp(r'^https?://\S+$', caseSensitive: false);

class _DeltaBuilder {
  final List<Map<String, dynamic>> _ops = [];
  bool _lineHasText = false;

  void visitChildren(
    dom.Node node,
    Map<String, Object> inline, {
    required int depth,
    Map<String, Object> block = const {},
  }) {
    for (final child in node.nodes) {
      visit(child, inline, depth: depth + 1, block: block);
    }
  }

  void visit(
    dom.Node node,
    Map<String, Object> inline, {
    required int depth,
    required Map<String, Object> block,
  }) {
    if (node is dom.Text) {
      _text(node.data.replaceAll(RegExp(r'[\r\n\t]+'), ' '), inline);
      return;
    }
    if (node is! dom.Element) return;
    if (depth > _maxDepth) {
      _text(node.text, inline);
      return;
    }
    final tag = node.localName;
    switch (tag) {
      case 'br':
        _newline(block);
      case 'b' || 'strong':
        visitChildren(
          node,
          {...inline, 'bold': true},
          depth: depth,
          block: block,
        );
      case 'i' || 'em':
        visitChildren(
          node,
          {...inline, 'italic': true},
          depth: depth,
          block: block,
        );
      case 'u':
        visitChildren(
          node,
          {...inline, 'underline': true},
          depth: depth,
          block: block,
        );
      case 's' || 'strike' || 'del':
        visitChildren(
          node,
          {...inline, 'strike': true},
          depth: depth,
          block: block,
        );
      case 'mark':
        visitChildren(
          node,
          {...inline, 'background': _markColor},
          depth: depth,
          block: block,
        );
      case 'a':
        final href = node.attributes['href']?.trim() ?? '';
        visitChildren(
          node,
          _safeHref.hasMatch(href) && href.length <= 2000
              ? {...inline, 'link': href}
              : inline,
          depth: depth,
          block: block,
        );
      case 'span' || 'font':
        final size = _sizeOf(node);
        visitChildren(
          node,
          size == null ? inline : {...inline, 'size': size},
          depth: depth,
          block: block,
        );
      case 'p' || 'div':
        _blockElement(node, inline, block, depth);
      case 'h2' || 'h3':
        _blockElement(node, inline, {
          ...block,
          'header': tag == 'h2' ? 2 : 3,
        }, depth);
      case 'blockquote':
        _blockElement(node, inline, {...block, 'blockquote': true}, depth);
      case 'ul' || 'ol':
        for (final item in node.children.where((c) => c.localName == 'li')) {
          _blockElement(item, inline, {
            ...block,
            'list': tag == 'ul' ? 'bullet' : 'ordered',
          }, depth + 1);
        }
      default:
        visitChildren(node, inline, depth: depth, block: block);
    }
  }

  void _blockElement(
    dom.Element node,
    Map<String, Object> inline,
    Map<String, Object> block,
    int depth,
  ) {
    if (_lineHasText) _newline(const {});
    visitChildren(node, inline, depth: depth, block: block);
    if (_lineHasText) _newline(block);
  }

  void _text(String text, Map<String, Object> inline) {
    if (text.isEmpty) return;
    if (!_lineHasText) text = text.trimLeft();
    if (text.isEmpty) return;
    _ops.add({'insert': text, if (inline.isNotEmpty) 'attributes': inline});
    _lineHasText = true;
  }

  void _newline(Map<String, Object> block) {
    _ops.add({'insert': '\n', if (block.isNotEmpty) 'attributes': block});
    _lineHasText = false;
  }

  static double? _sizeOf(dom.Element element) {
    final style = element.attributes['style'] ?? '';
    final keyword = RegExp(
      r'font-size\s*:\s*([a-z-]+)',
    ).firstMatch(style)?.group(1);
    if (keyword != null) return _fontSizes[keyword];
    final level = int.tryParse(element.attributes['size'] ?? '');
    if (level == null) return null;
    const byLevel = [null, 12.0, 12.0, null, 20.0, 24.0, 28.0, 28.0];
    return level >= 1 && level <= 7 ? byLevel[level] : null;
  }

  String? build() {
    if (!_ops.any((op) => (op['insert'] as String).trim().isNotEmpty)) {
      return null;
    }
    if (_lineHasText) _newline(const {});
    return jsonEncode(_ops);
  }
}

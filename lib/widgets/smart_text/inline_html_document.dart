/// ייצוג ביניים (IR) של שורת HTML שכל ה-markup שבה inline, לרינדור ב-Text.rich.
///
/// הבנייה מחקה את flutter_widget_from_html_core (fwfh) צעד אחר צעד: אותו פרסר
/// HTML, אותו פרסר CSS, אותו סדר החלת הצהרות ואותם כללי רווחים — כך שהספאנים
/// זהים לאלה ש-HtmlWidget היה בונה. markup שאינו מומר במדויק מחזיר null.
///
/// ה-IR אינו תלוי בהקשר: צבעי ערכת הנושא נשמרים כ-[InlineColorRole], ו-recognizers
/// נבנים רק בזמן הבנייה ([InlineHtmlText]) — ולכן שינוי ערכת נושא אינו מפרסר שוב.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart'
    show
        CssDeclarationExtension,
        CssFunctionTermExtension,
        CssLiteralTermExtension,
        CssNumberTermExtension,
        CssPercentageTermExtension,
        CssStyleSheetExtension,
        DomElementExtension;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/exact_line_height.dart';
import 'package:otzaria/widgets/smart_text/inline_html_tokenizer.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/smart_text_css.dart';

/// צבע שנקבע בזמן הבנייה מערכת הנושא.
enum InlineColorRole {
  /// צבע קישורי הספר (`AppSurfaces.readerLink`), אטום כמו ב-CSS.
  readerLink,

  /// ברירת המחדל של fwfh ל-`<a href>` (`colorScheme.primary`).
  primary,
}

/// רצף טקסט בסגנון אחד. [style] הוא ההפרש מסגנון השורה; צבע שתלוי בערכת
/// הנושא חסר בו ומסומן ב-[colorRole]/[decorationColorRole].
@immutable
class InlineRun {
  const InlineRun(
    this.text,
    this.style, {
    this.link = -1,
    this.colorRole,
    this.decorationColorRole,
  });

  final String text;
  final TextStyle? style;

  /// אינדקס ב-[InlineHtmlDocument.links], או -1.
  final int link;
  final InlineColorRole? colorRole;
  final InlineColorRole? decorationColorRole;

  /// [style] עם צבעי ערכת הנושא של [colorRole]/[decorationColorRole].
  TextStyle? resolvedStyle({
    required Color linkColor,
    required Color primaryColor,
  }) {
    if (colorRole == null && decorationColorRole == null) return style;
    Color? colorOf(InlineColorRole? role) => switch (role) {
      InlineColorRole.readerLink => linkColor,
      InlineColorRole.primary => primaryColor,
      null => null,
    };
    return (style ?? const TextStyle()).copyWith(
      color: colorOf(colorRole),
      decorationColor: colorOf(decorationColorRole),
    );
  }
}

/// קישור `<a href>`: [href] כפי שנכתב, [url] כפי ש-fwfh מעביר ללחיצה.
@immutable
class InlineLink {
  const InlineLink(this.href, this.url);

  final String href;
  final String url;
}

/// תוכן שורה מוכן לרינדור: [style] הוא סגנון השורה (סגנון כותרת בשורת כותרת).
class InlineHtmlLine {
  InlineHtmlLine(this.style, this.document, {required this.isHeading});

  final TextStyle style;
  final InlineHtmlDocument document;
  final bool isHeading;

  /// קיבוע גובה השורה; נקבע לפי גדלי הגופן בלבד, ולא לפי צבעים וקישורים.
  late final StrutStyle? strutStyle = exactLineHeightStrut(
    style,
    document.staticSpan ??
        TextSpan(
          children: [
            for (final run in document.runs)
              TextSpan(text: run.text, style: run.style),
          ],
        ),
  );
}

class InlineHtmlDocument {
  InlineHtmlDocument._(this.runs, this.links)
    : plainText = runs.map((run) => run.text).join(),
      hasThemeColors = runs.any(
        (run) => run.colorRole != null || run.decorationColorRole != null,
      );

  final List<InlineRun> runs;
  final List<InlineLink> links;

  /// הטקסט כפי שיוצג ויועתק.
  final String plainText;

  /// יש צבע שתלוי בערכת הנושא, ולכן אין [staticSpan].
  final bool hasThemeColors;

  /// ספאן שטוח שאינו תלוי בהקשר, כשאין קישורים ואין צבעי ערכת נושא.
  late final TextSpan? staticSpan = links.isNotEmpty || hasThemeColors
      ? null
      : TextSpan(
          children: [
            for (final run in runs) TextSpan(text: run.text, style: run.style),
          ],
        );

  /// מנסה להמיר את [html] (אחרי processText) לשורה. null — נדרש HtmlWidget.
  ///
  /// התוצאה (גם null) נשמרת ב-LRU לפי (html, סגנון, גופן משתנה).
  static InlineHtmlLine? parseLine(String html, TextStyle baseStyle) {
    if (html.isEmpty || html.length > _cacheMaxChars) {
      return _parseLineUncached(html, baseStyle);
    }
    // גופן מערכת משתנה מזוהה ברקע ומשנה את fontVariations של הבולד.
    final key = (
      html,
      baseStyle,
      AppFonts.boldFontVariations(baseStyle.fontFamily) != null,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached.$1;
    }
    final result = _parseLineUncached(html, baseStyle);
    if (result == null) SmartTextRenderStats.fullPathHtml(html);
    // אומדן: כל רצף הוא ספאן וסגנון.
    final nodes = 1 + 2 * (result?.document.runs.length ?? 0);
    if (nodes > _cacheMaxNodes) return result;
    _cache[key] = (result, nodes);
    _cacheChars += html.length;
    _cacheNodes += nodes;
    while (_cacheChars > _cacheMaxChars ||
        _cacheNodes > _cacheMaxNodes ||
        _cache.length > _cacheMaxEntries) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey)!;
      _cacheChars -= oldestKey.$1.length;
      _cacheNodes -= removed.$2;
    }
    return result;
  }

  static final LinkedHashMap<(String, TextStyle, bool), (InlineHtmlLine?, int)>
  _cache = LinkedHashMap();
  static int _cacheChars = 0;
  static int _cacheNodes = 0;
  static const int _cacheMaxChars = 2 * 1024 * 1024;
  static const int _cacheMaxEntries = 4096;
  static const int _cacheMaxNodes = 32 * 1024;

  @visibleForTesting
  static void clearCacheForTesting() {
    _cache.clear();
    _cacheChars = 0;
    _cacheNodes = 0;
  }

  static InlineHtmlLine? _parseLineUncached(String html, TextStyle baseStyle) {
    final List<dom.Node> nodes = html.contains('<') || html.contains('&')
        ? parseWellFormedInlineHtml(html) ??
              html_parser.parseFragment(html).nodes
        : [dom.Text(html)];
    final heading = _wholeLineHeading(nodes);
    if (heading != null) {
      final style = SimpleInlineHtml.headingStyleForTag(
        heading.localName!,
        baseStyle,
      );
      if (style == null) return null;
      final document = _InlineBuilder(
        style,
        inheritedVariations: baseStyle.fontVariations,
        rootFontSize: baseStyle.fontSize,
      ).build(heading.nodes);
      if (document == null || document.plainText.isEmpty) return null;
      return InlineHtmlLine(style, document, isHeading: true);
    }
    final document = _InlineBuilder(baseStyle).build(nodes);
    if (document == null) return null;
    return InlineHtmlLine(baseStyle, document, isHeading: false);
  }

  /// כותרת שהיא כל השורה (`<hN>` בלי attributes): fwfh מציג אותה כבלוק יחיד
  /// שהשוליים שלו נחתכים בקצות הגוף.
  static dom.Element? _wholeLineHeading(List<dom.Node> nodes) {
    dom.Element? heading;
    for (final node in nodes) {
      if (node is dom.Text) {
        if (!_isAllWhitespace(node.data)) return null;
        continue;
      }
      if (node is! dom.Element) continue;
      if (heading != null ||
          !_headingTags.contains(node.localName) ||
          node.attributes.isNotEmpty) {
        return null;
      }
      heading = node;
    }
    return heading;
  }

  static const Set<String> _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
}

bool _isAsciiSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;

bool _isAllWhitespace(String text) {
  for (var i = 0; i < text.length; i++) {
    if (!_isAsciiSpace(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// ערך הצבע כפי ש-fwfh מחזיק אותו: קבוע, currentcolor, או צבע ערכת נושא.
@immutable
class _CssColor {
  const _CssColor.value(Color this.color) : role = null, isCurrent = false;
  const _CssColor.role(InlineColorRole this.role)
    : color = null,
      isCurrent = false;
  const _CssColor.current() : color = null, role = null, isCurrent = true;

  final Color? color;
  final InlineColorRole? role;
  final bool isCurrent;
}

/// ה-InheritedProperties של fwfh לאלמנט: מה שעובר בירושה לצאצאים.
class _Props {
  _Props({
    required this.parent,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.fontWeight,
    required this.fontStyle,
    required this.decoration,
    required this.decorationStyle,
    required this.decorationThickness,
    required this.color,
    required this.decorationColor,
    required this.background,
    required this.nowrap,
    required this.link,
  }) : hasCallbacks = true;

  _Props.child(_Props this.parent)
    : fontSize = parent.fontSize,
      fontFamily = parent.fontFamily,
      fontFamilyFallback = parent.fontFamilyFallback,
      fontWeight = parent.fontWeight,
      fontStyle = parent.fontStyle,
      decoration = parent.decoration,
      decorationStyle = parent.decorationStyle,
      decorationThickness = parent.decorationThickness,
      color = parent.color,
      decorationColor = parent.decorationColor,
      background = parent.background,
      nowrap = parent.nowrap,
      link = parent.link,
      hasCallbacks = false;

  final _Props? parent;
  double? fontSize;
  String? fontFamily;
  List<String>? fontFamilyFallback;
  FontWeight? fontWeight;
  FontStyle? fontStyle;
  TextDecoration? decoration;
  TextDecorationStyle? decorationStyle;
  double? decorationThickness;

  /// null — הצבע של שורש השורה (DefaultTextStyle).
  _CssColor? color;
  _CssColor? decorationColor;
  _CssColor? background;
  bool nowrap;
  int link;

  /// האלמנט רשם ירושה משלו. בלעדיה fwfh רואה אותו כזהה להורה, ורצף טקסט
  /// שעובר דרכו נשאר באותו ספאן — וזה משנה את קיטום הרווחים בקצוות.
  bool hasCallbacks;
}

/// עלה בעץ הביטים של fwfh: טקסט, רווח או `<br>`.
class _Bit {
  _Bit.text(this.tree, this.data) : isWhitespace = false, isBreak = false;
  _Bit.whitespace(this.tree, this.data) : isWhitespace = true, isBreak = false;
  _Bit.lineBreak(this.tree) : data = '\n', isWhitespace = false, isBreak = true;

  final _Tree tree;
  final String data;
  final bool isWhitespace;
  final bool isBreak;
  late int index;

  /// כמו `BuildBit.swallowWhitespace`: טקסט inline לא בולע, רווח ו-br בולעים.
  bool get swallowsWhitespace => isWhitespace || isBreak;
}

class _Tree {
  _Tree(this.parent, this.props);

  final _Tree? parent;
  final _Props props;
  final List<Object> children = [];

  _Bit? get first {
    for (final child in children) {
      final bit = child is _Tree ? child.first : child as _Bit;
      if (bit != null) return bit;
    }
    return null;
  }

  _Bit? get last {
    for (final child in children.reversed) {
      final bit = child is _Tree ? child.last : child as _Bit;
      if (bit != null) return bit;
    }
    return null;
  }

  void collectBits(List<_Bit> out) {
    for (final child in children) {
      if (child is _Tree) {
        child.collectBits(out);
      } else {
        out.add(child as _Bit);
      }
    }
  }
}

/// מחרוזת בספאן, כמו `_String` של ה-Flattener.
class _Str {
  const _Str(this.data, {this.isWhitespace = false, this.swallowed = false});

  final String data;
  final bool isWhitespace;
  final bool swallowed;
}

/// סימן מוסכם בערכי CSS של [smartTextElementCss] לצבע שתלוי בערכת הנושא.
const String _kLinkColorToken = 'otzaria-reader-link';
const String _kHeadingColorToken = 'otzaria-section-heading';

class _Unsupported implements Exception {
  const _Unsupported();
}

class _InlineBuilder {
  _InlineBuilder(
    this.baseStyle, {
    List<FontVariation>? inheritedVariations,
    double? rootFontSize,
  }) : inheritedVariations = inheritedVariations ?? baseStyle.fontVariations,
       rootFontSize = rootFontSize ?? baseStyle.fontSize;

  /// סגנון השורש של הספאנים (בכותרת — סגנון הכותרת).
  final TextStyle baseStyle;

  /// ה-fontVariations שב-HtmlWidget עוברות בירושה לכל ספאן (של סגנון השורה).
  final List<FontVariation>? inheritedVariations;

  /// גודל השורש של HtmlWidget, שאליו יחסיים `medium`, `large` וכו' — גם בכותרת.
  final double? rootFontSize;
  final List<InlineLink> _links = [];

  InlineHtmlDocument? build(List<dom.Node> nodes) {
    final rootProps = _Props(
      parent: null,
      fontSize: baseStyle.fontSize,
      fontFamily: baseStyle.fontFamily,
      fontFamilyFallback: baseStyle.fontFamilyFallback,
      fontWeight: baseStyle.fontWeight,
      fontStyle: baseStyle.fontStyle,
      decoration: baseStyle.decoration,
      decorationStyle: baseStyle.decorationStyle,
      decorationThickness: baseStyle.decorationThickness,
      color: null,
      decorationColor: null,
      background: null,
      nowrap: false,
      link: -1,
    );
    final root = _Tree(null, rootProps);
    try {
      _addNodes(root, nodes);
      final runs = _flatten(root);
      if (runs == null) return null;
      return InlineHtmlDocument._(
        List.unmodifiable(runs),
        List.unmodifiable(_links),
      );
    } on _Unsupported {
      return null;
    }
  }

  void _addNodes(_Tree tree, List<dom.Node> nodes) {
    for (final node in nodes) {
      if (node is dom.Text) {
        _addText(tree, node.data);
      } else if (node is dom.Element) {
        final props = _resolveElement(node, tree.props);
        final sub = _Tree(tree, props);
        _addNodes(sub, node.nodes);
        if (node.localName == 'br') sub.children.add(_Bit.lineBreak(sub));
        tree.children.add(sub);
      }
    }
  }

  /// `_addText` של fwfh: רווח בודד נשאר בתוך הטקסט, רצפים אחרים הם ביטי רווח.
  void _addText(_Tree tree, String data) {
    var start = 0;
    while (start < data.length && _isAsciiSpace(data.codeUnitAt(start))) {
      start++;
    }
    var end = data.length;
    while (end > start && _isAsciiSpace(data.codeUnitAt(end - 1))) {
      end--;
    }
    if (end <= start) {
      if (data.isNotEmpty) tree.children.add(_Bit.whitespace(tree, data));
      return;
    }
    if (start > 0) {
      tree.children.add(_Bit.whitespace(tree, data.substring(0, start)));
    }
    var offset = start;
    var i = start;
    while (i < end) {
      if (!_isAsciiSpace(data.codeUnitAt(i))) {
        i++;
        continue;
      }
      var spaceEnd = i + 1;
      while (spaceEnd < end && _isAsciiSpace(data.codeUnitAt(spaceEnd))) {
        spaceEnd++;
      }
      if (spaceEnd - i == 1 && data.codeUnitAt(i) == 0x20) {
        i = spaceEnd;
        continue;
      }
      tree.children
        ..add(_Bit.text(tree, data.substring(offset, i)))
        ..add(_Bit.whitespace(tree, data.substring(i, spaceEnd)));
      offset = spaceEnd;
      i = spaceEnd;
    }
    tree.children.add(_Bit.text(tree, data.substring(offset, end)));
    if (end < data.length) {
      tree.children.add(_Bit.whitespace(tree, data.substring(end)));
    }
  }

  // ---------------------------------------------------------------- styles

  static const Set<String> _italicTags = {'i', 'em', 'cite', 'dfn', 'var'};
  static const Set<String> _plainTags = {
    'span',
    'a',
    'b',
    'strong',
    'big',
    'small',
    'u',
    'ins',
    's',
    'strike',
    'del',
    'mark',
    'br',
    ..._italicTags,
  };

  /// ה-attributes ש-fwfh מגיב אליהם מחוץ לתגים הנתמכים כאן.
  static const Set<String> _blockingAttributes = {'id', 'align'};

  _Props _resolveElement(dom.Element element, _Props parent) {
    final tag = element.localName;
    if (tag == null || !_plainTags.contains(tag)) throw const _Unsupported();
    final attributes = element.attributes;
    for (final name in attributes.keys) {
      if (_blockingAttributes.contains(name)) throw const _Unsupported();
    }
    final hasHref = tag == 'a' && attributes.containsKey('href');
    if (tag == 'a' && attributes.containsKey('name')) {
      throw const _Unsupported();
    }

    final props = _Props.child(parent);
    // 1. הירושות שתג האלמנט רושם (`WidgetFactory.parse`), לפני ההצהרות.
    if (hasHref) {
      props.color = const _CssColor.role(InlineColorRole.primary);
      props.hasCallbacks = true;
    }
    switch (tag) {
      case 'b' || 'strong':
        props.fontWeight = FontWeight.bold;
        props.hasCallbacks = true;
      case 'big':
        props.fontSize = _multiply(parent.fontSize, 1.2);
        props.hasCallbacks = true;
      case 'small':
        props.fontSize = _multiply(parent.fontSize, 15 / 18);
        props.hasCallbacks = true;
    }
    if (_italicTags.contains(tag)) {
      props.fontStyle = FontStyle.italic;
      props.hasCallbacks = true;
    }

    // 2. ההצהרות לפי סדרן: ברירות המחדל של התג, ה-CSS המותאם, ו-style.
    final declarations = <css.Declaration>[
      ..._tagDefaultDeclarations(tag, hasHref),
      ..._customDeclarations(element, hasHref),
      ...element.styles,
    ];
    for (final declaration in declarations) {
      _applyDeclaration(props, parent, declaration);
    }
    if (attributes.containsKey('dir')) {
      final dir = attributes['dir']!;
      if (dir != 'rtl') throw const _Unsupported();
      props.hasCallbacks = true;
    }
    _applyBackground(props, declarations);

    if (hasHref) {
      final href = attributes['href']!;
      props.link = _links.length;
      _links.add(InlineLink(href, _urlFull(href) ?? href));
    }
    return props;
  }

  static List<css.Declaration> _tagDefaultDeclarations(
    String tag,
    bool hasHref,
  ) => switch (tag) {
    'a' when hasHref => _declarations('text-decoration: underline'),
    'u' || 'ins' => _declarations('text-decoration-line: underline'),
    's' || 'strike' || 'del' => _declarations(
      'text-decoration-line: line-through',
    ),
    'mark' => _declarations('background-color: #ff0; color: #000'),
    _ => const [],
  };

  /// ה-CSS תלוי רק בתג, במחרוזת המחלקות וב-href; אלמנט כותרת אינו מגיע לכאן.
  static List<css.Declaration> _customDeclarations(
    dom.Element element,
    bool hasHref,
  ) {
    final key = (element.localName, element.className, hasHref);
    final cached = _customCache[key];
    if (cached != null) return cached;
    final map = smartTextElementCss(
      element.localName,
      element.classes,
      hasHref: hasHref,
      fontFamily: null,
      linkColorCss: _kLinkColorToken,
      headingColorCss: _kHeadingColorToken,
    );
    final declarations = map == null || map.isEmpty
        ? const <css.Declaration>[]
        : _declarations(
            map.entries.map((e) => '${e.key}: ${e.value}').join(';'),
          );
    if (_customCache.length >= 512) _customCache.clear();
    return _customCache[key] = declarations;
  }

  static final Map<(String?, String, bool), List<css.Declaration>>
  _customCache = {};

  static final Map<String, List<css.Declaration>> _declarationsCache = {};

  /// פרסור כמו `css.parse('*{...}')` של fwfh; המחרוזות כאן קבועות ומעטות.
  static List<css.Declaration> _declarations(String source) =>
      _declarationsCache[source] ??= css_parser
          .parse('*{$source}')
          .collectDeclarations();

  static double? _multiply(double? value, double factor) =>
      value == null ? null : value * factor;

  /// `parseStyle` של fwfh, מצומצם לתכונות שמתורגמות במדויק ל-TextStyle.
  void _applyDeclaration(
    _Props props,
    _Props parent,
    css.Declaration declaration,
  ) {
    final property = declaration.property;
    switch (property) {
      case 'color':
        final color = _parseColor(declaration.value);
        // currentcolor אינו משנה דבר: fwfh קורא כאן רק ערך קבוע.
        if (color != null && !color.isCurrent) {
          props.color = color;
          props.hasCallbacks = true;
        }
      case 'direction':
        final term = declaration.term;
        if (term == 'ltr') throw const _Unsupported();
        if (term != null) props.hasCallbacks = true;
      case 'font-family':
        final families = <String>[
          for (final value in declaration.values)
            if (value is css.LiteralTerm && value.valueAsString.isNotEmpty)
              value.valueAsString,
        ];
        if (families.isNotEmpty) props.fontFamily = families.first;
        props.fontFamilyFallback = families.skip(1).toList(growable: false);
        props.hasCallbacks = true;
      case 'font-size':
        final value = declaration.value;
        if (value == null) return;
        props.hasCallbacks = true;
        final size = _fontSize(value, parent);
        if (size != null) props.fontSize = size;
      case 'font-style':
        switch (declaration.term) {
          case 'italic':
            props.fontStyle = FontStyle.italic;
            props.hasCallbacks = true;
          case 'normal':
            props.fontStyle = FontStyle.normal;
            props.hasCallbacks = true;
        }
      case 'font-weight':
        final weight = _fontWeight(declaration.value);
        if (weight != null) {
          props.fontWeight = weight;
          props.hasCallbacks = true;
        }
      case 'text-decoration' ||
          'text-decoration-color' ||
          'text-decoration-line' ||
          'text-decoration-style' ||
          'text-decoration-thickness' ||
          'text-decoration-width':
        _applyTextDecoration(props, parent, declaration);
      case 'white-space':
        switch (declaration.term) {
          case 'normal':
            props.nowrap = false;
            props.hasCallbacks = true;
          case 'nowrap':
            props.nowrap = true;
            props.hasCallbacks = true;
          case 'pre':
            throw const _Unsupported();
        }
      case 'display':
        switch (declaration.term) {
          case 'block' || 'inline-block' || 'none' || 'flex' || 'table':
            throw const _Unsupported();
        }
      case 'height' ||
          'max-height' ||
          'max-width' ||
          'min-height' ||
          'min-width' ||
          'width' ||
          'line-height' ||
          'max-lines' ||
          '-webkit-line-clamp' ||
          'text-align' ||
          'text-emphasis' ||
          'text-emphasis-color' ||
          'text-emphasis-style' ||
          'text-overflow' ||
          'vertical-align' ||
          'text-shadow':
        throw const _Unsupported();
      default:
        if (property == 'background-color') return;
        if (property.startsWith('background') ||
            property.startsWith('border') ||
            property.startsWith('margin') ||
            property.startsWith('padding')) {
          throw const _Unsupported();
        }
    }
  }

  /// `StyleBackground`: הצבע התקף האחרון של background-color, בירושה לצאצאים.
  static void _applyBackground(
    _Props props,
    List<css.Declaration> declarations,
  ) {
    _CssColor? color;
    for (final declaration in declarations) {
      if (declaration.property != 'background-color') continue;
      final values = declaration.values;
      final parsed = values.isEmpty ? null : _parseColor(values.first);
      if (parsed != null) color = parsed;
    }
    if (color != null) {
      props.background = color;
      props.hasCallbacks = true;
    }
  }

  double? _fontSize(css.Expression value, _Props parent) {
    final base = parent.fontSize;
    if (value is css.EmTerm) {
      return _multiply(base, (value.value as num).toDouble());
    }
    if (value is css.LengthTerm) throw const _Unsupported();
    if (value is css.PercentageTerm) {
      return _multiply(base, (value.value as num).toDouble() / 100);
    }
    if (value is css.NumberTerm) {
      if (value.number == 0) throw const _Unsupported();
      return null;
    }
    if (value is css.LiteralTerm) {
      final rootSize = rootFontSize;
      return switch (value.valueAsString) {
        'xxx-large' => _multiply(rootSize, 3.0),
        'xx-large' => _multiply(rootSize, 2.0),
        'x-large' => _multiply(rootSize, 1.5),
        'large' => _multiply(rootSize, 1.125),
        'medium' => _multiply(rootSize, 1),
        'small' => _multiply(rootSize, .8125),
        'x-small' => _multiply(rootSize, .625),
        'xx-small' => _multiply(rootSize, .5625),
        'larger' => _multiply(base, 1.2),
        'smaller' => _multiply(base, 15 / 18),
        _ => null,
      };
    }
    return null;
  }

  static FontWeight? _fontWeight(css.Expression? value) {
    if (value is! css.LiteralTerm) return null;
    if (value is css.NumberTerm) {
      switch (value.number) {
        case 100:
          return FontWeight.w100;
        case 200:
          return FontWeight.w200;
        case 300:
          return FontWeight.w300;
        case 400:
          return FontWeight.w400;
        case 500:
          return FontWeight.w500;
        case 600:
          return FontWeight.w600;
        case 700:
          return FontWeight.w700;
        case 800:
          return FontWeight.w800;
        case 900:
          return FontWeight.w900;
        default:
          break;
      }
    }
    return value.valueAsString == 'bold' ? FontWeight.bold : null;
  }

  /// `textDecorationApply` של fwfh.
  static void _applyTextDecoration(
    _Props props,
    _Props parent,
    css.Declaration declaration,
  ) {
    final property = declaration.property;
    bool? over;
    bool? strike;
    bool? under;
    var hasLine = false;
    for (final value in declaration.values) {
      if (property == 'text-decoration' || property == 'text-decoration-line') {
        final line = value is css.LiteralTerm ? value.valueAsString : null;
        final parsed = switch (line) {
          'line-through' => (null, true, null),
          'none' => (false, false, false),
          'overline' => (true, null, null),
          'underline' => (null, null, true),
          _ => null,
        };
        if (parsed != null) {
          hasLine = true;
          over = parsed.$1 ?? over;
          strike = parsed.$2 ?? strike;
          under = parsed.$3 ?? under;
          continue;
        }
      }
      if (property == 'text-decoration' ||
          property == 'text-decoration-style') {
        final style = value is css.LiteralTerm
            ? switch (value.valueAsString) {
                'dotted' => TextDecorationStyle.dotted,
                'dashed' => TextDecorationStyle.dashed,
                'double' => TextDecorationStyle.double,
                'solid' => TextDecorationStyle.solid,
                'wavy' => TextDecorationStyle.wavy,
                _ => null,
              }
            : null;
        if (style != null) {
          props.decorationStyle = style;
          props.hasCallbacks = true;
          continue;
        }
      }
      if (property == 'text-decoration' ||
          property == 'text-decoration-color') {
        final color = _parseColor(value);
        if (color != null) {
          props.decorationColor = color;
          props.hasCallbacks = true;
          continue;
        }
      }
      if (property == 'text-decoration' ||
          property == 'text-decoration-thickness' ||
          property == 'text-decoration-width') {
        if (value is css.PercentageTerm) {
          props.decorationThickness = (value.value as num).toDouble() / 100.0;
          props.hasCallbacks = true;
          continue;
        }
      }
    }
    if (!hasLine) return;
    props.hasCallbacks = true;

    // כל הצהרה מחליפה את קווי האלמנט, אך צאצא אינו יכול להסיר קו של האב.
    final parentDecoration = parent.decoration;
    bool has(TextDecoration? decoration, TextDecoration line) =>
        decoration?.contains(line) == true;
    final list = <TextDecoration>[
      if (has(parentDecoration, TextDecoration.overline) || (over ?? false))
        TextDecoration.overline,
      if (has(parentDecoration, TextDecoration.lineThrough) ||
          (strike ?? false))
        TextDecoration.lineThrough,
      if (has(parentDecoration, TextDecoration.underline) || (under ?? false))
        TextDecoration.underline,
    ];
    props.decoration = TextDecoration.combine(list);
  }

  /// `tryParseColor` של fwfh, ושני הסימנים של צבעי ערכת הנושא.
  static _CssColor? _parseColor(css.Expression? expression) {
    if (expression == null) return null;
    if (expression is css.FunctionTerm) {
      final params = expression.params;
      switch (expression.text) {
        case 'hsl' || 'hsla':
          if (params.length < 3) return null;
          final param0 = params[0];
          final double? h;
          if (param0 is css.NumberTerm) {
            h = _hue(param0.number);
          } else if (param0 is css.AngleTerm) {
            h = _hue(param0.value as num, param0.unit);
          } else {
            h = null;
          }
          final param1 = params[1];
          final s = param1 is css.PercentageTerm
              ? param1.valueAsDouble.clamp(0.0, 1.0)
              : null;
          final param2 = params[2];
          final l = param2 is css.PercentageTerm
              ? param2.valueAsDouble.clamp(0.0, 1.0)
              : null;
          final a = params.length >= 4 ? _alpha(params[3]) : 1.0;
          if (h == null || s == null || l == null || a == null) return null;
          return _CssColor.value(HSLColor.fromAHSL(a, h, s, l).toColor());
        case 'rgb' || 'rgba':
          if (params.length < 3) return null;
          final r = _rgbElement(params[0]);
          final g = _rgbElement(params[1]);
          final b = _rgbElement(params[2]);
          final a = params.length >= 4 ? _alpha(params[3]) : 1.0;
          if (r == null || g == null || b == null || a == null) return null;
          return _CssColor.value(Color.fromARGB((a * 255).ceil(), r, g, b));
      }
      return null;
    }
    if (expression is css.HexColorTerm) {
      final hex = expression.text.toUpperCase();
      String x2(String value) => value.split('').map((c) => c * 2).join();
      final argb = switch (hex.length) {
        3 => 'FF${x2(hex)}',
        4 => '${x2(hex[3])}${x2(hex.substring(0, 3))}',
        6 => 'FF$hex',
        8 => '${hex.substring(6, 8)}${hex.substring(0, 6)}',
        _ => null,
      };
      // csslib מחזיר HexColorTerm גם ל-`#ggg`; fwfh (הפורק) מתעלם ממנו.
      final value = argb == null ? null : int.tryParse(argb, radix: 16);
      return value == null ? null : _CssColor.value(Color(value));
    }
    if (expression is css.LiteralTerm) {
      return switch (expression.valueAsString) {
        'currentcolor' => const _CssColor.current(),
        'transparent' => const _CssColor.value(Color(0x00000000)),
        _kLinkColorToken => const _CssColor.role(InlineColorRole.readerLink),
        // צבע כותרת הקטע שייך ל-h3 בלבד, שאינו נתמך כאן.
        _kHeadingColorToken => throw const _Unsupported(),
        _ => null,
      };
    }
    return null;
  }

  static double? _alpha(css.Expression expression) {
    final double? value;
    if (expression is css.NumberTerm) {
      value = expression.number.toDouble();
    } else if (expression is css.PercentageTerm) {
      value = expression.valueAsDouble;
    } else {
      value = null;
    }
    return value?.clamp(0, 1).toDouble();
  }

  static double _hue(num number, [int? unit]) {
    final v = number.toDouble();
    var deg = switch (unit) {
      css_parser.TokenKind.UNIT_ANGLE_RAD => v * (180 / math.pi),
      css_parser.TokenKind.UNIT_ANGLE_GRAD => v * 0.9,
      css_parser.TokenKind.UNIT_ANGLE_TURN => v * 360,
      _ => v,
    };
    while (deg < 0) {
      deg += 360;
    }
    return deg % 360;
  }

  static int? _rgbElement(css.Expression expression) {
    final int? value;
    if (expression is css.NumberTerm) {
      value = expression.number.ceil();
    } else if (expression is css.PercentageTerm) {
      value = (expression.valueAsDouble * 255.0).ceil();
    } else {
      value = null;
    }
    return value?.clamp(0, 255).toInt();
  }

  /// `WidgetFactory.urlFull` בלי baseUrl.
  static String? _urlFull(String url) {
    if (url.isEmpty) return null;
    if (url.startsWith('data:')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.hasScheme) return url;
    if (uri.hasAuthority) {
      return Uri(scheme: 'https').resolveUri(uri).toString();
    }
    return null;
  }

  // --------------------------------------------------------------- flatten

  /// ה-Flattener של fwfh: מחלק את הביטים לספאנים לפי עץ הסגנון, וקובע לכל
  /// רווח את הסגנון ואת הבליעה שלו.
  List<InlineRun>? _flatten(_Tree root) {
    final bits = <_Bit>[];
    root.collectBits(bits);
    for (var i = 0; i < bits.length; i++) {
      bits[i].index = i;
    }
    _Bit? nextNonWhitespace(_Bit bit) {
      for (var i = bit.index + 1; i < bits.length; i++) {
        if (!bits[i].isWhitespace) return bits[i];
      }
      return null;
    }

    final firstStrings = <_Str>[];
    final spans = <(_Tree, List<_Str>)>[];
    var currentTree = root;
    var strings = firstStrings;
    var swallow = false;

    void saveSpan() {
      if (!identical(strings, firstStrings) && strings.isNotEmpty) {
        spans.add((currentTree, strings));
      }
      strings = <_Str>[];
    }

    for (final bit in bits) {
      final effective = _effectiveTree(bit, nextNonWhitespace);
      final tree = effective == null ? currentTree : _resolverOwner(effective);
      if (!identical(tree, currentTree)) saveSpan();
      currentTree = tree;
      if (bit.isWhitespace) {
        strings.add(_Str(bit.data, isWhitespace: true, swallowed: swallow));
      } else {
        strings.add(_Str(bit.data));
      }
      swallow = bit.swallowsWhitespace;
    }
    saveSpan();

    // הבנייה של fwfh רצה מהסוף: הספאן האחרון שאינו ריק הוא "האחרון".
    final texts = List<String?>.filled(spans.length, null);
    var isLast = true;
    for (var i = spans.length - 1; i >= 0; i--) {
      final text = _toText(
        spans[i].$2,
        nowrap: spans[i].$1.props.nowrap,
        isFirst: false,
        isLast: isLast,
      );
      if (text.isNotEmpty) {
        texts[i] = text;
        isLast = false;
      }
    }
    final rootText = _toText(
      firstStrings,
      nowrap: root.props.nowrap,
      isFirst: true,
      isLast: isLast,
    );
    if (rootText.isEmpty && texts.every((text) => text == null)) {
      // שורה שכולה `<br>`: fwfh מציג placeholder בגובה שורה.
      final nonWhitespace = firstStrings.where((s) => !s.isWhitespace);
      if (nonWhitespace.length == 1 && nonWhitespace.first.data == '\n') {
        return null;
      }
    }

    final runs = <InlineRun>[];
    if (rootText.isNotEmpty) runs.add(InlineRun(rootText, null));
    for (var i = 0; i < spans.length; i++) {
      final text = texts[i];
      if (text != null) runs.add(_runFor(text, spans[i].$1.props));
    }
    return runs;
  }

  /// `InheritanceResolvers.isIdenticalWith`: האב הקרוב שרשם ירושה.
  static _Tree _resolverOwner(_Tree tree) {
    var owner = tree;
    while (!owner.props.hasCallbacks && owner.parent != null) {
      owner = owner.parent!;
    }
    return owner;
  }

  /// `effectiveInheritanceResolvers` של fwfh; null — הסגנון של הביט הקודם.
  static _Tree? _effectiveTree(
    _Bit bit,
    _Bit? Function(_Bit) nextNonWhitespace,
  ) {
    final parent = bit.tree;
    if (!bit.isWhitespace) return parent;
    if (identical(bit, parent.first)) return null;
    if (identical(bit, parent.last)) {
      final next = nextNonWhitespace(bit);
      if (next != null) {
        var tree = parent;
        while (identical(tree.parent!.last, bit)) {
          tree = tree.parent!;
        }
        return identical(tree.parent, next.tree) ? next.tree : null;
      }
    }
    return parent;
  }

  static String _toText(
    List<_Str> strings, {
    required bool nowrap,
    required bool isFirst,
    required bool isLast,
  }) {
    if (strings.isEmpty) return '';
    var min = 0;
    var max = strings.length - 1;
    if (isFirst) {
      while (min <= max && strings[min].isWhitespace) {
        min++;
      }
    }
    if (isLast) {
      while (max >= min && strings[max].isWhitespace) {
        max--;
      }
    }
    final buffer = StringBuffer();
    for (var i = min; i <= max; i++) {
      final str = strings[i];
      if (str.isWhitespace) {
        if (nowrap) {
          buffer.write('\u00A0');
        } else if (!str.swallowed) {
          buffer.write(' ');
        }
      } else {
        buffer.write(nowrap ? str.data.replaceAll(' ', '\u00A0') : str.data);
      }
    }
    final result = buffer.toString();
    if (isLast && result.endsWith('\n')) {
      return result.substring(0, result.length - 1);
    }
    return result;
  }

  /// `prepareTextStyle` של fwfh יחד עם ה-WidgetFactory של SmartTextWidget,
  /// כהפרש מסגנון השורה.
  InlineRun _runFor(String text, _Props props) {
    final base = baseStyle;
    InlineColorRole? colorRole;
    Color? color;
    switch (props.color) {
      case final _CssColor value?:
        colorRole = value.role;
        color = value.color;
      case null:
        break;
    }

    // currentcolor נפתר לצבע הטקסט של הספאן; צבע השורש — כמו בלי צבע.
    InlineColorRole? decorationColorRole;
    Color? decorationColor;
    final decoration = props.decorationColor;
    if (decoration != null) {
      if (decoration.isCurrent) {
        decorationColorRole = colorRole;
        decorationColor = color;
      } else {
        decorationColorRole = decoration.role;
        decorationColor = decoration.color;
      }
    }
    Color? backgroundColor;
    final background = props.background;
    if (background != null) {
      if (background.isCurrent || background.role != null) {
        throw const _Unsupported();
      }
      backgroundColor = background.color;
    }

    final fontFamily = props.fontFamily;
    final fontWeight = props.fontWeight;
    // הבולד האמיתי של ה-WidgetFactory: רק כשהספאן לא ירש fontVariations.
    final variations =
        inheritedVariations ??
        AppFonts.boldFontVariations(
          fontFamily,
          fontWeight ?? FontWeight.normal,
        );
    final fontVariations = listEquals(variations, base.fontVariations)
        ? null
        : (variations ?? const <FontVariation>[]);

    T? diff<T>(T? value, T? baseValue) => value == baseValue ? null : value;
    final familyChanged = fontFamily != base.fontFamily;
    final fallbackChanged = !listEquals(
      props.fontFamilyFallback,
      base.fontFamilyFallback,
    );
    final style = TextStyle(
      fontSize: diff(props.fontSize, base.fontSize),
      fontFamily: familyChanged ? fontFamily : null,
      fontFamilyFallback: fallbackChanged ? props.fontFamilyFallback : null,
      fontWeight: diff(fontWeight, base.fontWeight),
      fontStyle: diff(props.fontStyle, base.fontStyle),
      fontVariations: fontVariations,
      decoration: diff(props.decoration, base.decoration),
      decorationStyle: diff(props.decorationStyle, base.decorationStyle),
      decorationThickness: diff(
        props.decorationThickness,
        base.decorationThickness,
      ),
      color: color,
      decorationColor: decorationColor,
      background: backgroundColor == null
          ? null
          : (Paint()..color = backgroundColor),
    );
    return InlineRun(
      text,
      style == const TextStyle() ? null : style,
      link: props.link,
      colorRole: colorRole,
      decorationColorRole: decorationColorRole,
    );
  }
}

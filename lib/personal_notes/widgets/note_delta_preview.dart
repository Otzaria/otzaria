import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/personal_notes/widgets/personal_note_styles.dart';

/// מציג עיצובים נתמכים ב-RichText, לפי סגנונות ההערה ([personalNoteStyles])
/// וללא קלט.
class NoteDeltaPreview extends StatelessWidget {
  const NoteDeltaPreview({super.key, required this.document});

  final quill.Document document;

  /// עיצובים אחרים נשארים ב-Quill כדי לשמר את הרינדור שלו.
  static bool supports(quill.Document document) {
    if (document.root.children.any(
      (node) => node is! quill.Line || node.style.attributes.isNotEmpty,
    )) {
      return false;
    }
    return document.toDelta().operations.every((operation) {
      final attrs = operation.attributes ?? const <String, dynamic>{};
      return operation.data is String &&
          attrs.entries.every(
            (entry) => _supportsAttribute(entry.key, entry.value),
          );
    });
  }

  static bool _supportsAttribute(String key, Object? value) =>
      switch ((key, value)) {
        (
          'bold' || 'italic' || 'small' || 'underline' || 'strike',
          true,
        ) =>
          true,
        ('font' || 'link', String()) => true,
        ('size', num size) => size > 0 && size.isFinite,
        ('size', 'small' || 'large' || 'huge') => true,
        ('size', String size) => switch (double.tryParse(size)) {
          final parsed? => parsed > 0 && parsed.isFinite,
          null => false,
        },
        ('color' || 'background', String color) => RegExp(
          r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
        ).hasMatch(color),
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final styles = personalNoteStyles(context);
    final direction = Directionality.of(context);
    final children = [
      for (final line in document.root.children.whereType<quill.Line>())
        _rootLine(context, styles, line, direction),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _rootLine(
    BuildContext context,
    quill.DefaultStyles styles,
    quill.Line line,
    TextDirection direction,
  ) {
    final paragraph = styles.paragraph!;
    final horizontal = paragraph.horizontalSpacing;
    final vertical = paragraph.verticalSpacing;
    final body = _lineText(context, styles, line, direction);
    final decoration = paragraph.decoration;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: horizontal.left,
        end: horizontal.right,
        top: vertical.top,
        bottom: vertical.bottom,
      ),
      child: decoration == null
          ? body
          : DecoratedBox(decoration: decoration, child: body),
    );
  }

  Widget _lineText(
    BuildContext context,
    quill.DefaultStyles styles,
    quill.Line line,
    TextDirection direction,
  ) {
    final lineStyle = styles.paragraph!.style;
    final children = <InlineSpan>[
      for (final leaf in line.children)
        if (leaf is quill.QuillText)
          TextSpan(
            text: leaf.value,
            style: _inlineStyle(styles, leaf.style.attributes),
          ),
    ];
    return RichText(
      text: TextSpan(style: lineStyle, children: children),
      textAlign: TextAlign.start,
      textDirection: direction,
      strutStyle: StrutStyle.fromTextStyle(lineStyle),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  static TextStyle _inlineStyle(
    quill.DefaultStyles styles,
    Map<String, quill.Attribute> attrs,
  ) {
    var res = const TextStyle();
    final color = _parseColor(attrs[quill.Attribute.color.key]?.value);
    void add(String key, TextStyle? style) {
      if (style == null || !attrs.containsKey(key)) return;
      if (key == quill.Attribute.link.key && attrs[key]!.value == null) {
        return;
      }
      final isLineDecoration =
          key == quill.Attribute.underline.key ||
          key == quill.Attribute.strikeThrough.key;
      final decorationColor = color ?? styles.color;
      res = _mergeDecorations(
        isLineDecoration ? res.copyWith(decorationColor: decorationColor) : res,
        isLineDecoration
            ? style.copyWith(decorationColor: decorationColor)
            : style,
      );
    }

    add(quill.Attribute.bold.key, styles.bold);
    add(quill.Attribute.italic.key, styles.italic);
    add(quill.Attribute.small.key, styles.small);
    add(quill.Attribute.link.key, styles.link);
    add(quill.Attribute.underline.key, styles.underline);
    add(quill.Attribute.strikeThrough.key, styles.strikeThrough);

    final font = attrs[quill.Attribute.font.key]?.value;
    if (font is String) res = res.merge(TextStyle(fontFamily: font));

    final size = _fontSizeOf(styles, attrs[quill.Attribute.size.key]?.value);
    if (size != null) res = res.merge(TextStyle(fontSize: size));
    if (color != null) res = res.merge(TextStyle(color: color));

    final background = _parseColor(
      attrs[quill.Attribute.background.key]?.value,
    );
    if (background != null) {
      res = res.merge(TextStyle(backgroundColor: background));
    }
    return res;
  }

  static TextStyle _mergeDecorations(TextStyle a, TextStyle b) {
    final decorations = [?a.decoration, ?b.decoration];
    return a.merge(b).apply(decoration: TextDecoration.combine(decorations));
  }

  static double? _fontSizeOf(quill.DefaultStyles styles, Object? value) {
    return switch (value) {
      'small' => styles.sizeSmall?.fontSize,
      'large' => styles.sizeLarge?.fontSize,
      'huge' => styles.sizeHuge?.fontSize,
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
  }

  static Color? _parseColor(Object? value) {
    if (value is! String || !value.startsWith('#')) return null;
    var hex = value.substring(1);
    if (hex.length == 6) hex = 'ff$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;

import '../models/editor_settings.dart';
import 'markdown_processor.dart';

/// Service for rendering markdown preview using HtmlWidget
class PreviewRenderer {
  final MarkdownProcessor _processor;

  PreviewRenderer({
    EditorSettings? settings,
    MarkdownProcessor? processor,
  }) : _processor = processor ?? const MarkdownProcessor();

  /// Renders markdown content as a widget with debounced updates
  Widget renderPreview({
    required String markdown,
    required TextStyle textStyle,
    String? fontFamily,
  }) {
    if (markdown.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Text(
          'תצוגה מקדימה תופיע כאן...',
          style: textStyle.copyWith(
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
          textDirection: TextDirection.rtl,
        ),
      );
    }

    try {
      final html = _processor.markdownToHtml(markdown);

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HtmlWidget(
          html,
          textStyle: textStyle.copyWith(
            fontFamily: fontFamily,
            height: 1.5,
          ),
          customStylesBuilder: (element) {
            return _getCustomStyles(element, textStyle);
          },
          onTapUrl: (url) {
            // Handle URL taps - could open in browser or show warning
            return _handleUrlTap(url);
          },
        ),
      );
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Text(
          'שגיאה בתצוגה מקדימה: ${e.toString()}',
          style: textStyle.copyWith(color: Colors.red),
          textDirection: TextDirection.rtl,
        ),
      );
    }
  }

// lib/text_book/editing/services/preview_renderer.dart

  /// Gets custom styles for HTML elements
  Map<String, String>? _getCustomStyles(
    dom.Element element,
    TextStyle baseStyle,
  ) {
    final styles = <String, String>{};

    // Base text direction
    styles['direction'] = 'rtl';
    styles['text-align'] = 'justify';

    switch (element.localName) {
      case 'code':
      case 'pre':
        styles['direction'] = 'ltr';
        styles['text-align'] = 'left';
        styles['font-family'] = 'monospace';
        styles['background-color'] = '#f5f5f5';
        styles['padding'] = '4px 8px';
        styles['border-radius'] = '4px';
        break;

      case 'blockquote':
        styles['border-right'] = '4px solid #ddd';
        styles['padding-right'] = '16px';
        styles['margin-right'] = '0';
        styles['font-style'] = 'italic';
        break;

      case 'h1':
        styles['font-size'] = '${baseStyle.fontSize! * 1.5}px';
        styles['font-weight'] = 'bold';
        styles['margin-top'] = '6px'; // רווח קטן לפני הכותרת
        styles['margin-bottom'] = '3px'; // רווח קטן אחרי הכותרת
        break;

      case 'h2':
        styles['font-size'] = '${baseStyle.fontSize! * 1.3}px';
        styles['font-weight'] = 'bold';
        styles['margin-top'] = '4px';
        styles['margin-bottom'] = '2px';
        break;

      case 'h3':
        styles['font-size'] = '${baseStyle.fontSize! * 1.1}px';
        styles['font-weight'] = 'bold';
        styles['margin-top'] = '3px';
        styles['margin-bottom'] = '2px';
        break;

      case 'ul':
      case 'ol':
        styles['padding-right'] = '20px';
        break;

      case 'li':
        styles['margin-bottom'] = '4px';
        break;

      case 'a':
        styles['color'] = '#2196F3';
        styles['text-decoration'] = 'underline';
        break;
    }

    return styles.isEmpty ? null : styles;
  }

  /// Handles URL taps in the preview
  bool _handleUrlTap(String url) {
    // For security, we'll just return false to prevent navigation
    return false;
  }
}

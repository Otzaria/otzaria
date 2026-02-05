import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/html_link_handler.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// ווידג'ט חכם להצגת טקסט עברי
///
/// מרכז את כל הלוגיקה של עיבוד והצגת טקסט במקום אחד:
/// - הסרת ניקוד וטעמים
/// - החלפת שמות קדושים
/// - הדגשת תוצאות חיפוש
/// - עיצוב סוגריים
/// - טיפול בקישורים פנימיים
class SmartTextWidget extends StatelessWidget {
  /// הטקסט הגולמי להצגה (יכול להכיל HTML)
  final String text;

  /// הגדרות הרינדור
  final RenderSettings settings;

  /// callback לפתיחת ספר/טאב
  final Function(OpenedTab)? onOpenBook;

  /// מפתח ייחודי לווידג'ט (לאופטימיזציה)
  final Key? widgetKey;

  /// מצב רינדור של HtmlWidget
  final RenderMode renderMode;

  const SmartTextWidget({
    super.key,
    required this.text,
    required this.settings,
    this.onOpenBook,
    this.widgetKey,
    this.renderMode = RenderMode.column,
  });

  @override
  Widget build(BuildContext context) {
    // עיבוד הטקסט דרך השירות המרכזי
    final processedHtml = TextRendererService.render(text, settings);

    if (processedHtml.contains('<sup') ||
        processedHtml.contains('footnote-marker') ||
        processedHtml.contains('¹') ||
        processedHtml.contains('²') ||
        processedHtml.contains('³')) {
      assert(() {
        final supRegex = RegExp(
          r'<sup[^>]*>(.*?)</sup>',
          caseSensitive: false,
          dotAll: true,
        );
        final markers = <String>[];
        for (final match in supRegex.allMatches(processedHtml)) {
          final inner = (match.group(1) ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll('\u2066', '')
              .replaceAll('\u2067', '')
              .replaceAll('\u2068', '')
              .replaceAll('\u2069', '');
          if (inner.isNotEmpty) {
            markers.add(inner);
          }
        }
        if (markers.length >= 2) {
          debugPrint(
              '[SmartTextWidget] markers sequence: ${markers.join(', ')}');
        }
        return true;
      }());

      final preview = processedHtml.length > 400
          ? '${processedHtml.substring(0, 400)}…'
          : processedHtml;
      debugPrint('[SmartTextWidget] HTML with <sup>: $preview');
    }

    return HtmlWidget(
      processedHtml,
      key: widgetKey,
      renderMode: renderMode,
      textStyle: TextStyle(
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
        height: settings.lineHeight,
      ),
      customStylesBuilder: (dom.Element element) {
        if (element.localName == 'span' &&
            element.classes.contains('footnote-marker-number')) {
          return {
            'font-size': '0.75em',
            'font-style': 'italic',
            'position': 'relative',
            'top': '-0.55em',
          };
        }
        return null;
      },
      onTapUrl: onOpenBook != null
          ? (url) async {
              return await HtmlLinkHandler.handleLink(
                context,
                url,
                (tab) => onOpenBook!(tab),
              );
            }
          : null,
    );
  }
}

/// גרסה פשוטה יותר של SmartTextWidget שמקבלת פרמטרים בודדים
/// במקום RenderSettings - נוחה למקרים פשוטים
class SimpleSmartText extends StatelessWidget {
  final String text;
  final double fontSize;
  final String? fontFamily;
  final bool removeNikud;
  final bool removeTeamim;
  final bool replaceHolyNames;
  final String searchText;
  final Function(OpenedTab)? onOpenBook;
  final Key? widgetKey;

  const SimpleSmartText({
    super.key,
    required this.text,
    required this.fontSize,
    this.fontFamily,
    this.removeNikud = false,
    this.removeTeamim = true,
    this.replaceHolyNames = false,
    this.searchText = '',
    this.onOpenBook,
    this.widgetKey,
  });

  @override
  Widget build(BuildContext context) {
    return SmartTextWidget(
      text: text,
      settings: RenderSettings(
        fontSize: fontSize,
        fontFamily: fontFamily,
        removeNikud: removeNikud,
        removeTeamim: removeTeamim,
        replaceHolyNames: replaceHolyNames,
        searchText: searchText,
      ),
      onOpenBook: onOpenBook,
      widgetKey: widgetKey,
    );
  }
}

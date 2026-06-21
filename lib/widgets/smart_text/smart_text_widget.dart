import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
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

  /// callback ללחיצה על סימון הערה אישית inline.
  /// מקבל את אינדקס השורה (0-based) שעליה ההערה.
  final void Function(int lineIndex)? onNoteTap;

  /// מפתח ייחודי לווידג'ט (לאופטימיזציה)
  final Key? widgetKey;

  /// מצב רינדור של HtmlWidget
  final RenderMode renderMode;

  const SmartTextWidget({
    super.key,
    required this.text,
    required this.settings,
    this.onOpenBook,
    this.onNoteTap,
    this.widgetKey,
    this.renderMode = RenderMode.column,
  });

  @override
  Widget build(BuildContext context) {
    // עיבוד הטקסט דרך השירות המרכזי
    final processedHtml = TextRendererService.render(text, settings);

    return HtmlWidget(
      processedHtml,
      key: widgetKey,
      renderMode: renderMode,
      textStyle: TextStyle(
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
        fontWeight: settings.fontWeight,
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
      onTapUrl: (onOpenBook != null || onNoteTap != null)
          ? (url) async {
              // סימון הערה אישית inline — נטפל לפני שאר הקישורים.
              if (url.startsWith('otzaria://note')) {
                final lineIndex =
                    int.tryParse(Uri.parse(url).queryParameters['line'] ?? '');
                if (lineIndex != null) {
                  onNoteTap?.call(lineIndex);
                }
                return true;
              }
              if (onOpenBook == null) return false;
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

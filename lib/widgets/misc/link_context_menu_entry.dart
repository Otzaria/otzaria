import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// בונה פריט תפריט הקשר עבור קישור בודד בתת-תפריט "קישורים".
///
/// מאחד מימוש שהיה משוכפל בתצוגה המשולבת, בצורת הדף וב-PDF: תווית עם
/// כתובת תצוגה מלאה (נטענת ברקע), פתיחת היעד בלחיצה, וחלונית תצוגה
/// מקדימה צפה עם תוכן הקישור ברפרוף ([AppContextMenuEntry.hoverPreviewBuilder]).
AppContextMenuEntry buildLinkContextMenuEntry({
  required Link link,
  required VoidCallback onTap,
  bool? removeNikud,
  bool? removePunctuation,
}) {
  return AppContextMenuEntry(
    label: link.fallbackDisplayReference,
    labelWidget: FutureBuilder<String>(
      future: link.displayReference,
      builder: (context, snapshot) => Text(
        snapshot.data ?? link.fallbackDisplayReference,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    onTap: onTap,
    hoverPreviewBuilder: (context) => LinkHoverPreviewContent(
      link: link,
      removeNikud: removeNikud,
      removePunctuation: removePunctuation,
    ),
  );
}

/// תוכן חלונית התצוגה המקדימה של קישור — כותרת (כתובת היעד) ותוכן הקטע,
/// מעוצב לפי הגדרות תצוגת המפרשים (גופן, ניקוד, טעמים).
class LinkHoverPreviewContent extends StatefulWidget {
  final Link link;

  /// כשמסופק — תוכן המפרש נחתך לגובה של [maxContentLines] שורות, ומופיע לחצן
  /// "…" כשהתוכן ארוך מהחיתוך; לחיצה עליו פורשת אותו לתצוגה נגללת מלאה.
  final int? maxContentLines;

  /// כותרת זעירה ומרווחים צמודים — לחלונית קופצת קטנה (עוגן-מילה).
  final bool compact;

  /// כשמסופק — הכותרת הופכת ללחיצה (מעבר ליעד) ומופיע לצידה אייקון פתיחה.
  final VoidCallback? onOpen;

  /// מצב הניקוד/פיסוק של הטאב שממנו נפתחה החלונית. כשמסופק — גובר על
  /// ההגדרות הגלובליות, כדי שהתצוגה המקדימה תשקף את מה שהמשתמש רואה בטאב.
  final bool? removeNikud;
  final bool? removePunctuation;

  const LinkHoverPreviewContent({
    super.key,
    required this.link,
    this.maxContentLines,
    this.compact = false,
    this.onOpen,
    this.removeNikud,
    this.removePunctuation,
  });

  @override
  State<LinkHoverPreviewContent> createState() =>
      _LinkHoverPreviewContentState();
}

class _LinkHoverPreviewContentState extends State<LinkHoverPreviewContent> {
  /// חלק מגובה המסך שהתוכן הפרוש מוגבל אליו, לפני הגלילה הפנימית.
  static const double _expandedScreenFraction = 0.6;
  static const double _expandedMaxHeight = 420;

  bool _expanded = false;

  Link get link => widget.link;
  int? get maxContentLines => widget.maxContentLines;
  bool get compact => widget.compact;
  VoidCallback? get onOpen => widget.onOpen;
  bool? get removeNikud => widget.removeNikud;
  bool? get removePunctuation => widget.removePunctuation;

  double get _expandedHeight =>
      (MediaQuery.sizeOf(context).height * _expandedScreenFraction).clamp(
        0.0,
        _expandedMaxHeight,
      );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final colorScheme = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<String>(
              future: link.displayReference,
              builder: (context, snapshot) {
                var title = snapshot.data ?? link.fallbackDisplayReference;
                if (settingsState.replaceHolyNames) {
                  title = utils.replaceHolyNames(title);
                }
                final titleText = Text(
                  title,
                  maxLines: compact ? 1 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    fontSize: compact
                        ? 11
                        : settingsState.commentatorsFontSize - 2,
                    fontWeight: FontWeight.bold,
                    fontFamily: settingsState.commentatorsFontFamily,
                    color: colorScheme.primary,
                  ),
                );
                if (onOpen == null) return titleText;
                return InkWell(
                  onTap: onOpen,
                  child: Row(
                    children: [
                      Expanded(child: titleText),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.open_in_new,
                        size: compact ? 13 : 16,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                );
              },
            ),
            Divider(height: compact ? 8 : 16),
            FutureBuilder<String>(
              future: link.content,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'שגיאה בטעינת התוכן',
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: settingsState.commentatorsFontSize - 2,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  final placeholderHeight = maxContentLines != null
                      ? settingsState.commentatorsFontSize *
                            settingsState.lineHeight *
                            maxContentLines!
                      : 72.0;
                  return SizedBox(
                    height: placeholderHeight,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final cleanContent =
                    TextRendererService.stripHtml(
                          snapshot.data!,
                        )
                        .replaceAll('&nbsp;', ' ')
                        .replaceAll(RegExp(r'[^\S\r\n]+'), ' ')
                        .trim();
                if (cleanContent.isEmpty) {
                  return Text(
                    'אין תוכן זמין',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: settingsState.commentatorsFontSize - 2,
                    ),
                  );
                }

                final removePunctuation = this.removePunctuation ?? false;
                return FutureBuilder<bool>(
                  future: removeNikud != null
                      ? Future.value(removeNikud)
                      : resolveRemoveNikudForBook(
                          title: utils.getTitleFromPath(link.path2),
                          defaultRemoveNikud: settingsState.defaultRemoveNikud,
                          removeNikudFromTanach:
                              settingsState.removeNikudFromTanach,
                        ),
                  builder: (context, nikudSnapshot) {
                    final content = SmartTextWidget(
                      text: cleanContent,
                      settings: RenderSettings(
                        removeNikud: nikudSnapshot.data ?? false,
                        removePunctuation: removePunctuation,
                        removeTeamim: !settingsState.showTeamim,
                        replaceHolyNames: settingsState.replaceHolyNames,
                        fontSize: settingsState.commentatorsFontSize,
                        fontFamily: settingsState.commentatorsFontFamily,
                        fontWeight: settingsState.commentatorsFontBold
                            ? FontWeight.bold
                            : null,
                        lineHeight: settingsState.lineHeight,
                        justifyText: true,
                      ),
                    );
                    if (maxContentLines == null) return content;
                    if (_expanded) {
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: _expandedHeight,
                        ),
                        child: SingleChildScrollView(child: content),
                      );
                    }
                    final fontSize = settingsState.commentatorsFontSize;
                    final lineHeight = settingsState.lineHeight;
                    final maxHeight = fontSize * lineHeight * maxContentLines!;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // מדידה על הטקסט כפי שירונדר (בלי ניקוד אם צריך) כדי
                        // להחליט אם התוכן נגזר ולהציג "…".
                        var measureText = cleanContent;
                        if (nikudSnapshot.data ?? false) {
                          measureText = utils.removeVolwels(measureText);
                        }
                        if (removePunctuation) {
                          measureText = utils.removePunctuation(measureText);
                        }
                        final painter = TextPainter(
                          text: TextSpan(
                            text: measureText,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontFamily: settingsState.commentatorsFontFamily,
                              height: lineHeight,
                              fontWeight: settingsState.commentatorsFontBold
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                          textDirection: TextDirection.rtl,
                          maxLines: null,
                        )..layout(maxWidth: constraints.maxWidth);
                        final truncated = painter.height > maxHeight + 1;
                        painter.dispose();

                        final clipped = ClipRect(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxHeight),
                            child: content,
                          ),
                        );
                        if (!truncated) return clipped;
                        return Stack(
                          children: [
                            clipped,
                            Positioned(
                              bottom: 0,
                              left: 0,
                              child: _ExpandContentButton(
                                fontSize: fontSize,
                                fontFamily:
                                    settingsState.commentatorsFontFamily,
                                lineHeight: lineHeight,
                                onPressed: () =>
                                    setState(() => _expanded = true),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// לחצן "…" בתחתית תוכן חתוך — לחיצה פורשת את התוכן לתצוגה נגללת.
class _ExpandContentButton extends StatelessWidget {
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final VoidCallback onPressed;

  const _ExpandContentButton({
    required this.fontSize,
    required this.fontFamily,
    required this.lineHeight,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Tooltip(
        message: 'הצגת כל התוכן',
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '…',
              style: TextStyle(
                fontSize: fontSize,
                fontFamily: fontFamily,
                height: lineHeight,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

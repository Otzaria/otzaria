import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';

class CommentaryContent extends StatefulWidget {
  const CommentaryContent({
    super.key,
    required this.link,
    required this.fontSize,
    required this.openBookCallback,
    required this.removeNikud,
    this.removePunctuation = false,
    this.searchQuery = '',
    this.currentSearchIndex = 0,
    this.onSearchResultsCountChanged,
    this.onSearchSnippetsChanged,
    this.onRendered,
  });
  final bool removeNikud;
  final bool removePunctuation;
  final Link link;
  final double fontSize;
  final Function(TextBookTab) openBookCallback;
  final String searchQuery;
  final int currentSearchIndex;
  final Function(int)? onSearchResultsCountChanged;
  final Function(List<String>)? onSearchSnippetsChanged;

  /// מדווח את הטקסט הפשוט המרונדר (כפי שמופיע במסך) — משמש לשחזור מעברי שורה
  /// בהעתקה רב-שורתית של מפרשים.
  final void Function(String renderedPlainText)? onRendered;

  @override
  State<CommentaryContent> createState() => _CommentaryContentState();
}

class _CommentaryContentState extends State<CommentaryContent> {
  late Future<String> content;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  void _loadContent() {
    // Validate link before loading content
    if (widget.link.path2.isEmpty || widget.link.index2 <= 0) {
      content = Future<String>.error(
        StateError('Invalid link reference for commentary content'),
      );
    } else {
      content = widget.link.content;
    }
  }

  @override
  void didUpdateWidget(CommentaryContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון תוכן הפירוש כאשר הקישור משתנה
    // בודקים אם הקישור השתנה על ידי השוואת המאפיינים המזהים שלו
    if (oldWidget.link.path2 != widget.link.path2 ||
        oldWidget.link.index2 != widget.link.index2 ||
        oldWidget.link.heRef != widget.link.heRef) {
      setState(() {
        _loadContent();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        widget.openBookCallback(
          TextBookTab(
            book: TextBook(
              title: utils.getTitleFromPath(widget.link.path2),
              isUserBook: widget.link.targetIsUserBook,
              categoryId: widget.link.targetCategoryId,
              fileType: widget.link.targetFileType,
            ),
            index: widget.link.index2 - 1,
            openLeftPane:
                (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
          ),
        );
      },
      child: AppFutureBuilder<String>(
        future: content,
        loadingWidget: _buildSkeletonLoading(context),
        errorBuilder: (context, error) => Center(
          child: Text('שגיאה בטעינת הפרשן: $error'),
        ),
        builder: (context, data) {
          return BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              // מצב הניקוד/פיסוק של הטאב חל על כל המפרשים כפי שהוא,
              // ללא רזולוציה פר-ספר-יעד.
              if (widget.searchQuery.isNotEmpty) {
                final searchCount = countCommentarySearchMatches(
                  content: data,
                  query: widget.searchQuery,
                  removePunctuation: widget.removePunctuation,
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.onSearchResultsCountChanged?.call(searchCount);
                  if (widget.onSearchSnippetsChanged != null &&
                      searchCount > 0) {
                    widget.onSearchSnippetsChanged!.call([
                      buildCommentarySearchSnippet(
                        content: data,
                        query: widget.searchQuery,
                        removeNikud: widget.removeNikud,
                        removePunctuation: widget.removePunctuation,
                      ),
                    ]);
                  }
                });
              }

              final renderSettings = RenderSettings(
                removeNikud: widget.removeNikud,
                removePunctuation: widget.removePunctuation,
                removeTeamim: !settingsState.showTeamim,
                replaceHolyNames: settingsState.replaceHolyNames,
                searchText: widget.searchQuery,
                currentSearchIndex: widget.currentSearchIndex,
                fontSize: widget.fontSize,
                fontFamily: settingsState.commentatorsFontFamily,
                fontWeight: settingsState.commentatorsFontBold
                    ? FontWeight.bold
                    : null,
                lineHeight: settingsState.lineHeight,
                partialWordHighlight: true,
              );

              _reportRenderedText(data, renderSettings);

              // עוגן בצד המקושר (ציטוט מ-charLevelData): הדגשת הטווח
              // המצוטט בתוך קטע המפרש, באופסטים של תווים-גלויים.
              var displayData = data;
              final linkedStart = widget.link.linkedAnchorStart;
              final linkedEnd = widget.link.linkedAnchorEnd;
              if (linkedStart != null &&
                  linkedEnd != null &&
                  linkedEnd > linkedStart) {
                displayData = wrapVisibleRange(
                  html: data,
                  start: linkedStart,
                  end: linkedEnd,
                  openTag: '<span class="link-anchor-range">',
                  closeTag: '</span>',
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SmartTextWidget(
                    text: displayData,
                    settings: renderSettings,
                  ),
                  LaazCommentarySubBlock(link: widget.link),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String? _lastRenderKey;

  /// מחשב את הטקסט הפשוט המרונדר (memoized) ומדווח אותו דרך [widget.onRendered]
  /// לאחר ה-frame — לשחזור מעברי שורה בהעתקה רב-שורתית.
  void _reportRenderedText(String data, RenderSettings settings) {
    if (widget.onRendered == null) return;
    // הטקסט הפשוט אינו תלוי בחיפוש/הדגשה (אלה מוסרים ב-stripHtml).
    final key =
        '${settings.removeNikud}|${settings.removePunctuation}|'
        '${settings.removeTeamim}|${settings.replaceHolyNames}|$data';
    if (key == _lastRenderKey) return;
    _lastRenderKey = key;
    final rendered = renderSelectionLine(rawText: data, settings: settings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRendered?.call(rendered);
    });
  }

  /// בניית skeleton loading לתוכן פרשנות - שלוש שורות
  Widget _buildSkeletonLoading(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _SkeletonLine(width: 0.95, height: 14, color: baseColor),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _SkeletonLine(width: 0.92, height: 14, color: baseColor),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _SkeletonLine(width: 0.88, height: 14, color: baseColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget של שורה סטטית לשלד טעינה
class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonLine({
    required this.width,
    required this.color,
    this.height = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppTokens.borderRadiusAll,
      ),
    );
  }
}

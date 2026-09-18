import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/middle_click_open.dart';
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/utils/note_inline_render.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';

@visibleForTesting
List<PersonalNote> commentaryNotesForLine(
  List<PersonalNote> notes,
  int lineNumber,
) => notes
    .where((note) => note.hasLocation && note.lineNumber == lineNumber)
    .toList();

@visibleForTesting
ValueChanged<int>? commentaryNoteTapHandler(
  BuildContext context,
  List<PersonalNote> notes,
) => notes.isEmpty
    ? null
    : (_) => showPersonalNotesDialog(context: context, notes: notes);

@visibleForTesting
void openCommentaryPersonalNote({
  required BuildContext context,
  required Link link,
  required List<PersonalNote> notes,
  void Function(Link link, int lineNumber)? onOpenPersonalNote,
}) {
  if (onOpenPersonalNote != null) {
    onOpenPersonalNote(link, link.index2);
    return;
  }
  showPersonalNotesDialog(context: context, notes: notes);
}

class CommentaryContent extends StatefulWidget {
  const CommentaryContent({
    super.key,
    required this.link,
    required this.fontSize,
    required this.openBookCallback,
    required this.displayProfile,
    this.searchQuery = '',
    this.currentSearchIndex = 0,
    this.onSearchResultsCountChanged,
    this.onSearchSnippetsChanged,
    this.onRendered,
    this.personalNotes,
    this.onOpenPersonalNote,
  });

  /// פרופיל תצוגת המפרשים של הכרטיסייה — חל על כל המפרשים כפי שהוא.
  final TextDisplayProfile displayProfile;
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

  /// הערות ספר המפרש. אותו Future משותף לכל קטעי המפרש בקבוצה.
  final Future<List<PersonalNote>>? personalNotes;
  final void Function(Link link, int lineNumber)? onOpenPersonalNote;

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
    return MiddleClickOpen(
      onMiddleClick: () =>
          ContextMenuUtils.openLinkTargetInBackground(context, widget.link),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        widget.openBookCallback(
          TextBookTab(
            book: TextBook(
              title: utils.getTitleFromPath(widget.link.path2),
              source: widget.link.targetSource,
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
              if (widget.searchQuery.isNotEmpty) {
                final searchCount = countCommentarySearchMatches(
                  content: data,
                  query: widget.searchQuery,
                  displayProfile: widget.displayProfile,
                  // כמו partialWordHighlight של הרינדור למטה — המונה חייב
                  // לספור את מה שנצבע (issue #1055).
                  partialWordMatch: true,
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.onSearchResultsCountChanged?.call(searchCount);
                  if (widget.onSearchSnippetsChanged != null &&
                      searchCount > 0) {
                    widget.onSearchSnippetsChanged!.call([
                      buildCommentarySearchSnippet(
                        content: data,
                        query: widget.searchQuery,
                        displayProfile: widget.displayProfile,
                      ),
                    ]);
                  }
                });
              }

              final renderSettings = RenderSettings.fromProfile(
                widget.displayProfile,
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

              return FutureBuilder<List<PersonalNote>>(
                future: widget.personalNotes,
                builder: (context, snapshot) {
                  // המפרש מרונדר מיד; הסימונים נוספים כשההערות נטענות. הסתרה
                  // עד לטעינה מעלימה את המפרש כשהטעינה נכשלת או נתקעת.
                  final notesForLine = commentaryNotesForLine(
                    snapshot.data ?? const <PersonalNote>[],
                    widget.link.index2,
                  );
                  var displayData = buildAnnotatedLineHtml(
                    rawLine: data,
                    notesForLine: notesForLine,
                    lineIndex0: widget.link.index2 - 1,
                    underlineColor: Theme.of(context).colorScheme.primary,
                  );

                  final linkedStart = widget.link.linkedAnchorStart;
                  final linkedEnd = widget.link.linkedAnchorEnd;
                  if (linkedStart != null &&
                      linkedEnd != null &&
                      linkedEnd > linkedStart) {
                    displayData = wrapVisibleRange(
                      html: displayData,
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
                        onNoteTap: notesForLine.isEmpty
                            ? null
                            : (_) => openCommentaryPersonalNote(
                                context: context,
                                link: widget.link,
                                notes: notesForLine,
                                onOpenPersonalNote: widget.onOpenPersonalNote,
                              ),
                      ),
                      LaazCommentarySubBlock(link: widget.link),
                    ],
                  );
                },
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
        '${settings.removeTeamim}|${settings.replaceHolyNames}|'
        '${settings.holyNameStyle.storageKey}|$data';
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

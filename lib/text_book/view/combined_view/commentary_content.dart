import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';

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

  @override
  State<CommentaryContent> createState() => _CommentaryContentState();
}

class _CommentaryContentState extends State<CommentaryContent> {
  late Future<String> content;
  Future<bool>? _removeNikudFuture;
  String? _removeNikudCacheKey;

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

  int _countSearchMatches(String text, String searchQuery) {
    return TextRendererService.countSearchMatches(text, searchQuery);
  }

  Future<bool> _resolveRemoveNikud(SettingsState settingsState) {
    final title = utils.getTitleFromPath(widget.link.path2);
    final cacheKey =
        '$title|${settingsState.defaultRemoveNikud}|${settingsState.removeNikudFromTanach}|${widget.removeNikud}';

    if (_removeNikudFuture != null && _removeNikudCacheKey == cacheKey) {
      return _removeNikudFuture!;
    }

    _removeNikudCacheKey = cacheKey;
    _removeNikudFuture = resolveRemoveNikudForBook(
      title: title,
      defaultRemoveNikud:
          settingsState.defaultRemoveNikud || widget.removeNikud,
      removeNikudFromTanach: settingsState.removeNikudFromTanach,
    );
    return _removeNikudFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        widget.openBookCallback(TextBookTab(
          book: TextBook(title: utils.getTitleFromPath(widget.link.path2)),
          index: widget.link.index2 - 1,
          openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
              (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
        ));
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
                return FutureBuilder<bool>(
                  future: _resolveRemoveNikud(settingsState),
                  initialData: widget.removeNikud,
                  builder: (context, snapshot) {
                    final effectiveRemoveNikud =
                        snapshot.data ?? widget.removeNikud;

                    if (widget.searchQuery.isNotEmpty) {
                      String textForCount = data;
                      if (effectiveRemoveNikud) {
                        textForCount = utils.removeVolwels(textForCount);
                      }
                      if (widget.removePunctuation) {
                        textForCount = utils.removePunctuation(textForCount);
                      }
                      final searchCount =
                          _countSearchMatches(textForCount, widget.searchQuery);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.onSearchResultsCountChanged?.call(searchCount);
                        if (widget.onSearchSnippetsChanged != null &&
                            searchCount > 0) {
                          final plainText =
                              utils.stripHtmlIfNeeded(textForCount);
                          final excerpt = SnippetBuilder.buildExcerptText(
                            fullText: plainText,
                            query: widget.searchQuery,
                            maxChars: 220,
                          );
                          widget.onSearchSnippetsChanged!.call([excerpt]);
                        }
                      });
                    }

                    return SmartTextWidget(
                      text: data,
                      settings: RenderSettings(
                        removeNikud: effectiveRemoveNikud,
                        removePunctuation: widget.removePunctuation,
                        removeTeamim: !settingsState.showTeamim,
                        replaceHolyNames: settingsState.replaceHolyNames,
                        searchText: widget.searchQuery,
                        currentSearchIndex: widget.currentSearchIndex,
                        fontSize: widget.fontSize,
                        fontFamily: settingsState.commentatorsFontFamily,
                        lineHeight: settingsState.lineHeight,
                      ),
                    );
                  },
                );
              },
            );
          }),
    );
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
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

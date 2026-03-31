import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/app_future_builder.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/utils/context_menu_utils.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_debug_logger.dart';

@visibleForTesting
RenderSettings buildSelectedLinkRenderSettings({
  required SettingsState settingsState,
  required bool removeNikud,
  required String searchText,
}) {
  return RenderSettings(
    removeNikud: removeNikud,
    removeTeamim: !settingsState.showTeamim,
    replaceHolyNames: settingsState.replaceHolyNames,
    searchText: searchText,
    fontSize: settingsState.commentatorsFontSize,
    fontFamily: settingsState.commentatorsFontFamily,
    lineHeight: settingsState.lineHeight,
    justifyText: false,
  );
}

@visibleForTesting
String normalizeSelectedLinkText(String text) {
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'[^\S\r\n]+'), ' ')
      .trim();
}

/// Widget שמציג את הקישורים של השורה הנבחרת בלבד
class SelectedLineLinksView extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final bool
      showVisibleLinksIfNoSelection; // האם להציג קישורים נראים אם אין בחירה

  const SelectedLineLinksView({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.showVisibleLinksIfNoSelection = false,
  });

  @override
  State<SelectedLineLinksView> createState() => _SelectedLineLinksViewState();
}

class _SelectedLineLinksViewState extends State<SelectedLineLinksView> {
  late final String _debugScope;
  int _buildCount = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, Future<String>> _contentCache = {};
  final Map<String, Future<bool>> _removeNikudCache = {};
  final Map<String, bool> _expanded = {};
  bool _searchInContent = false;
  Future<List<Link>>? _filteredLinksFuture;
  String _lastSearchKey = '';
  final Set<String> _linksWithSearchResults = {}; // קישורים עם תוצאות חיפוש
  String? _savedSelectedText; // טקסט נבחר לתפריט הקשר

  @override
  void initState() {
    super.initState();
    _debugScope = PageShapeDebugLogger.newScope('selected-line-links');
    PageShapeDebugLogger.log(
      'SelectedLineLinksView',
      'initState',
      scope: _debugScope,
      data: {
        'fontSize': widget.fontSize,
        'showVisibleLinksIfNoSelection': widget.showVisibleLinksIfNoSelection,
      },
      level: 'LIFECYCLE',
    );
  }

  @override
  void dispose() {
    PageShapeDebugLogger.log(
      'SelectedLineLinksView',
      'dispose',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
      },
      level: 'END',
    );
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    PageShapeDebugLogger.log(
      'SelectedLineLinksView',
      'build',
      scope: _debugScope,
      data: {
        'buildCount': _buildCount,
        'searchQueryLength': _searchQuery.length,
        'searchInContent': _searchInContent,
      },
      level: 'BUILD',
    );
    return TextBookStateBuilder(
      builder: (context, state) {
        return Column(
          children: [
            // שדה חיפוש
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  OtzariaSearchField(
                    controller: _searchController,
                    hintText: 'חפש בתוך הקישורים המוצגים...',
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    onClear: () {
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  ),
                  if (_searchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _searchInContent,
                            onChanged: (value) {
                              setState(() {
                                _searchInContent = value ?? false;
                              });
                            },
                          ),
                          const Text('חפש גם בתוכן הקישורים'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // תוכן הקישורים
            Expanded(
              child: _buildLinksList(state),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLinksList(TextBookLoaded state) {
    // מסנן קישורים מבוססי תווים (inline links) - הם אמורים להופיע רק בתוך הטקסט
    final links = state.visibleLinks
        .where((link) => link.start == null && link.end == null)
        .toList();

    if (links.isEmpty) {
      PageShapeDebugLogger.log(
        'SelectedLineLinksView',
        'לא נמצאו קישורים לשורה הנוכחית',
        scope: _debugScope,
        data: {
          'selectedIndex': state.selectedIndex,
          ...PageShapeDebugLogger.summarizeIndices(state.visibleIndices),
        },
      );
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'לא נמצאו קישורים לקטע הנבחר',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    // יצירת מפתח ייחודי לחיפוש
    final searchKey = '${_searchQuery}_${_searchInContent}_${links.length}';

    // יצירת Future חדש רק אם החיפוש השתנה
    if (_lastSearchKey != searchKey) {
      _lastSearchKey = searchKey;
      _filteredLinksFuture = _filterLinksAsync(links);
      PageShapeDebugLogger.log(
        'SelectedLineLinksView',
        'נוצר Future חדש לסינון קישורים',
        scope: _debugScope,
        data: {
          'searchKey': searchKey,
          'linksCount': links.length,
        },
      );
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: AppFutureBuilder<List<Link>>(
        future: _filteredLinksFuture,
        builder: (context, data) {
          final filteredLinks = data;

          return ListView.builder(
            itemCount: filteredLinks.length,
            itemBuilder: (context, index) {
              final link = filteredLinks[index];
              return _buildExpansionTile(link);
            },
          );
        },
      ),
    );
  }

  // פונקציה אסינכרונית לסינון הקישורים עם חיפוש בתוכן
  Future<List<Link>> _filterLinksAsync(List<Link> links) async {
    final trace = PageShapeDebugLogger.start(
      'SelectedLineLinksView',
      'סינון קישורים בחלונית קישורים',
      scope: _debugScope,
      data: {
        'linksCount': links.length,
        'searchQuery': _searchQuery,
        'searchInContent': _searchInContent,
      },
      longTaskAfter: const Duration(milliseconds: 300),
      heartbeatEvery: const Duration(milliseconds: 300),
    );
    _linksWithSearchResults.clear(); // איפוס רשימת הקישורים עם תוצאות

    if (_searchQuery.isEmpty) {
      trace.end(data: {'reason': 'empty query', 'linksCount': links.length});
      return links;
    }

    final query = _searchQuery.toLowerCase();
    final filteredLinks = <Link>[];

    for (final link in links) {
      final keyStr = '${link.path2}_${link.index2}';
      final title = link.heRef.toLowerCase();
      final bookTitle = utils.getTitleFromPath(link.path2).toLowerCase();

      // חיפוש בכותרת ושם הספר
      if (title.contains(query) || bookTitle.contains(query)) {
        filteredLinks.add(link);
        continue;
      }

      // חיפוש בתוכן אם הופעל
      if (_searchInContent) {
        try {
          final content = await link.content;
          final cleanContent = normalizeSelectedLinkText(
            utils.stripHtmlIfNeeded(content),
          ).toLowerCase();
          if (cleanContent.contains(query)) {
            filteredLinks.add(link);
            _linksWithSearchResults.add(keyStr); // מסמן שיש תוצאות בתוכן
            _contentCache[keyStr] = link.content; // טוען את התוכן למטמון

            // פותח אוטומטית את הקישור הראשון עם תוצאות
            if (_linksWithSearchResults.length == 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _expanded[keyStr] = true;
                  });
                }
              });
            }
          }
        } catch (e) {
          // אם יש שגיאה בטעינת התוכן, מוסיף בכל זאת אם מתאים לכותרת
          // (כבר בדקנו את זה למעלה)
          trace.warn(
            'שגיאה בטעינת תוכן קישור בזמן חיפוש',
            data: {
              'linkPath': link.path2,
              'linkIndex2': link.index2,
              'error': e,
            },
          );
        }
      }
    }

    trace.end(
      data: {
        'filteredLinksCount': filteredLinks.length,
        'linksWithSearchResultsCount': _linksWithSearchResults.length,
      },
    );
    return filteredLinks;
  }

  Future<bool> _resolveRemoveNikudForLink(
      Link link, SettingsState settingsState) {
    final title = utils.getTitleFromPath(link.path2);
    final cacheKey =
        '$title|${settingsState.defaultRemoveNikud}|${settingsState.removeNikudFromTanach}';

    return _removeNikudCache.putIfAbsent(
      cacheKey,
      () => resolveRemoveNikudForBook(
        title: title,
        defaultRemoveNikud: settingsState.defaultRemoveNikud,
        removeNikudFromTanach: settingsState.removeNikudFromTanach,
      ),
    );
  }

  Widget _buildExpansionTile(Link link) {
    final keyStr = '${link.path2}_${link.index2}';
    final restoredExpanded = PageStorage.maybeOf(context)?.readState(
          context,
          identifier: keyStr,
        ) as bool?;
    final isExpanded = _expanded[keyStr] ?? restoredExpanded ?? false;
    PageShapeDebugLogger.log(
      'SelectedLineLinksView',
      'בניית ExpansionTile לקישור',
      scope: _debugScope,
      data: {
        'key': keyStr,
        'isExpanded': isExpanded,
        'path2': link.path2,
        'index2': link.index2,
      },
      level: 'BUILD',
    );
    return ctx.ContextMenuRegion(
      contextMenu: ContextMenuUtils.buildCommentaryContextMenu(
        context: context,
        link: link,
        openBookCallback: widget.openBookCallback,
        fontSize: widget.fontSize,
        savedSelectedText: _savedSelectedText,
        onCopySelected: () => ContextMenuUtils.copyFormattedText(
          context: context,
          savedSelectedText: _savedSelectedText,
          fontSize: widget.fontSize,
        ),
      ),
      child: ExpansionTile(
        key: PageStorageKey(keyStr),
        initiallyExpanded: isExpanded,
        maintainState: true,
        showTrailingIcon: false,
        leading: AnimatedRotation(
          turns: isExpanded ? -0.25 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.keyboard_arrow_left,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
        title: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            String displayTitle = utils.getTitleFromPath(link.path2);
            if (settingsState.replaceHolyNames) {
              displayTitle = utils.replaceHolyNames(displayTitle);
            }
            return Text(
              displayTitle,
              style: TextStyle(
                fontSize: settingsState.commentatorsFontSize - 2,
                fontWeight: FontWeight.bold,
                fontFamily: settingsState.commentatorsFontFamily,
              ),
              textDirection: TextDirection.rtl,
            );
          },
        ),
        subtitle: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            return FutureBuilder<String>(
              future: link.displayReference,
              builder: (context, snapshot) {
                String displaySubtitle =
                    snapshot.data ?? link.fallbackDisplayReference;
                if (settingsState.replaceHolyNames) {
                  displaySubtitle = utils.replaceHolyNames(displaySubtitle);
                }
                return Text(
                  displaySubtitle,
                  style: TextStyle(
                    fontSize: settingsState.commentatorsFontSize - 4,
                    fontWeight: FontWeight.normal,
                    fontFamily: settingsState.commentatorsFontFamily,
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(128),
                  ),
                  textDirection: TextDirection.rtl,
                );
              },
            );
          },
        ),
        onExpansionChanged: (isExpanded) {
          // טוען תוכן רק אם נפתח ועדיין לא נטען
          if (isExpanded && !_contentCache.containsKey(keyStr)) {
            _contentCache[keyStr] = link.content;
          }

          // עדכון מצב ההרחבה עם setState בטוח - דוחה עד אחרי הבנייה
          if (_expanded[keyStr] != isExpanded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _expanded[keyStr] = isExpanded;
                });
              }
            });
          }
        },
        children: [
          if (isExpanded)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: AppFutureBuilder<String>(
                future: _contentCache[keyStr],
                builder: (context, content) => _buildLinkContent(content, link),
                errorBuilder: (context, error) =>
                    BlocBuilder<SettingsBloc, SettingsState>(
                  builder: (context, settingsState) {
                    return Text(
                      'שגיאה בטעינת התוכן: $error',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: settingsState.commentatorsFontSize,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinkContent(String content, Link link) {
    if (content.isEmpty) {
      return BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          return Text(
            'אין תוכן זמין',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              fontSize: settingsState.commentatorsFontSize,
            ),
          );
        },
      );
    }

    return GestureDetector(
      onTap: () {
        widget.openBookCallback(
          TextBookTab(
            book: TextBook(
              title: utils.getTitleFromPath(link.path2),
            ),
            index: link.index2 - 1,
            openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ??
                    false) ||
                (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12.0),
        child: _buildHighlightedText(content, link),
      ),
    );
  }

  Widget _buildHighlightedText(String content, Link link) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final cleanContent = normalizeSelectedLinkText(
          TextRendererService.stripHtml(content),
        );

        // חיפוש בתוכן - בדיקה אם הקישור הזה מכיל תוצאות
        String searchText = '';
        if (_searchQuery.isNotEmpty && _searchInContent) {
          final keyStr = '${link.path2}_${link.index2}';
          if (_linksWithSearchResults.contains(keyStr)) {
            searchText = _searchQuery;
          }
        }

        return FutureBuilder<bool>(
          future: _resolveRemoveNikudForLink(link, settingsState),
          builder: (context, snapshot) {
            return SmartTextWidget(
              text: cleanContent,
              settings: buildSelectedLinkRenderSettings(
                settingsState: settingsState,
                removeNikud: snapshot.data ?? false,
                searchText: searchText,
              ),
            );
          },
        );
      },
    );
  }
}

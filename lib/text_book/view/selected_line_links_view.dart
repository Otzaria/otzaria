import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';

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
    justifyText: true,
  );
}

@visibleForTesting
String normalizeSelectedLinkText(String text) {
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'[^\S\r\n]+'), ' ')
      .trim();
}

@visibleForTesting
String buildSelectedLinkContentKey(Link link) {
  return '${link.path2}_${link.index2}';
}

@visibleForTesting
String buildSelectedLinkInstanceKey(Link link) {
  return '${link.path2}_${link.index1}_${link.index2}_${link.heRef}_${link.start}_${link.end}_${link.connectionType}';
}

@visibleForTesting
String buildSelectedLinksSearchKey({
  required String searchQuery,
  required bool searchInContent,
  required List<Link> links,
}) {
  final linksSignature = links.map(buildSelectedLinkInstanceKey).join('|');
  return '${searchQuery}_$searchInContent|$linksSignature';
}

/// Widget שמציג את הקישורים של השורה הנבחרת בלבד
class SelectedLineLinksView extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final bool
      showVisibleLinksIfNoSelection; // האם להציג קישורים נראים אם אין בחירה
  final SelectionSyncController? selectionSyncController;

  const SelectedLineLinksView({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.showVisibleLinksIfNoSelection = false,
    this.selectionSyncController,
  });

  @override
  State<SelectedLineLinksView> createState() => _SelectedLineLinksViewState();
}

class _SelectedLineLinksViewState extends State<SelectedLineLinksView> {
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
  Link? _savedSelectedLink; // ה-link שממנו נבחר הטקסט
  final Object _selectionOwner = Object();
  int _selectionRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
  }

  @override
  void dispose() {
    widget.selectionSyncController
        ?.removeListener(_handleExternalSelectionChange);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SelectedLineLinksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController
          ?.removeListener(_handleExternalSelectionChange);
      widget.selectionSyncController
          ?.addListener(_handleExternalSelectionChange);
    }
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null ||
        controller.activeOwner == null ||
        identical(controller.activeOwner, _selectionOwner)) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectionRevision = controller.revision;
      _savedSelectedText = null;
      _savedSelectedLink = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      // רשימת הקישורים תלויה ב-visibleLinks בלבד (ובהצגת הטקסט), לא בתוכן
      // הספר. דילוג על emit-ים של warming/הרחבת-טווח שלא נוגעים לקישורים.
      buildWhen: (previous, current) {
        if (previous is! TextBookLoaded || current is! TextBookLoaded) {
          return true;
        }
        return previous.visibleLinks != current.visibleLinks ||
            previous.fontSize != current.fontSize ||
            previous.removeNikud != current.removeNikud ||
            previous.removePunctuation != current.removePunctuation;
      },
      builder: (context, state) {
        return Column(
          children: [
            // שדה חיפוש
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  RtlTextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'חפש בתוך הקישורים המוצגים...',
                      prefixIcon: const Icon(FluentIcons.search_24_regular),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(FluentIcons.dismiss_24_regular),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
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
    final searchKey = buildSelectedLinksSearchKey(
      searchQuery: _searchQuery,
      searchInContent: _searchInContent,
      links: links,
    );

    // יצירת Future חדש רק אם החיפוש השתנה
    if (_lastSearchKey != searchKey) {
      _lastSearchKey = searchKey;
      _filteredLinksFuture = _filterLinksAsync(links);
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
    _linksWithSearchResults.clear(); // איפוס רשימת הקישורים עם תוצאות

    // מיון הקישורים לפי סדר הדורות (כמו במפרשים)
    final sortedLinks = await CommentaryService.sortLinksByEra(links);

    if (_searchQuery.isEmpty) {
      return sortedLinks;
    }

    final query = _searchQuery.toLowerCase();
    final filteredLinks = <Link>[];

    for (final link in sortedLinks) {
      final instanceKey = buildSelectedLinkInstanceKey(link);
      final contentKey = buildSelectedLinkContentKey(link);
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
            _linksWithSearchResults.add(instanceKey); // מסמן שיש תוצאות בתוכן
            _contentCache[contentKey] = link.content; // טוען את התוכן למטמון

            // פותח אוטומטית את הקישור הראשון עם תוצאות
            if (_linksWithSearchResults.length == 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _expanded[instanceKey] = true;
                  });
                }
              });
            }
          }
        } catch (_) {
          // אם יש שגיאה בטעינת התוכן, מוסיף בכל זאת אם מתאים לכותרת
          // (כבר בדקנו את זה למעלה)
        }
      }
    }

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
    final instanceKey = buildSelectedLinkInstanceKey(link);
    final contentKey = buildSelectedLinkContentKey(link);
    final restoredExpanded = PageStorage.maybeOf(context)?.readState(
      context,
      identifier: instanceKey,
    ) as bool?;
    final isExpanded = _expanded[instanceKey] ?? restoredExpanded ?? false;
    return ExpansionTile(
      key: PageStorageKey(instanceKey),
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
          );
        },
      ),
      subtitle: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          final fallbackSubtitle = settingsState.replaceHolyNames
              ? utils.replaceHolyNames(link.fallbackDisplayReference)
              : link.fallbackDisplayReference;

          if (!isExpanded) {
            return Text(
              fallbackSubtitle,
              style: TextStyle(
                fontSize: settingsState.commentatorsFontSize - 4,
                fontWeight: FontWeight.normal,
                fontFamily: settingsState.commentatorsFontFamily,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
              ),
            );
          }

          return FutureBuilder<String>(
            future: link.displayReference,
            initialData: fallbackSubtitle,
            builder: (context, snapshot) {
              String displaySubtitle = snapshot.data ?? fallbackSubtitle;
              if (settingsState.replaceHolyNames) {
                displaySubtitle = utils.replaceHolyNames(displaySubtitle);
              }
              return Text(
                displaySubtitle,
                style: TextStyle(
                  fontSize: settingsState.commentatorsFontSize - 4,
                  fontWeight: FontWeight.normal,
                  fontFamily: settingsState.commentatorsFontFamily,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
                ),
              );
            },
          );
        },
      ),
      onExpansionChanged: (isExpanded) {
        // טוען תוכן רק אם נפתח ועדיין לא נטען
        if (isExpanded && !_contentCache.containsKey(contentKey)) {
          _contentCache[contentKey] = link.content;
        }

        // עדכון מצב ההרחבה עם setState בטוח - דוחה עד אחרי הבנייה
        if (_expanded[instanceKey] != isExpanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _expanded[instanceKey] = isExpanded;
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
              future: _contentCache[contentKey],
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

    return RtlSelectionShortcuts(
        child: SelectionArea(
      key: ValueKey(
        'selected_link_${buildSelectedLinkInstanceKey(link)}_$_selectionRevision',
      ),
      contextMenuBuilder: (context, selectableRegionState) {
        return const SizedBox.shrink();
      },
      onSelectionChanged: (selection) {
        // עדכון מעקב כיוון הגרירה (ל-RtlSelectionShortcuts).
        trackRtlSelection(selection?.plainText);
        // שינוי בחירה זמני בזמן priming — לא לעבד.
        if (rtlSelectionPriming) return;
        if (selection != null && selection.plainText.isNotEmpty) {
          widget.selectionSyncController?.activate(_selectionOwner);
          _savedSelectedText = selection.plainText;
          _savedSelectedLink = link;
        } else if (selection == null || selection.plainText.trim().isEmpty) {
          widget.selectionSyncController?.clear(_selectionOwner);
          _savedSelectedText = null;
          _savedSelectedLink = null;
        }
      },
      child: AppContextMenuRegion(
        // לחיצה ימנית על הטקסט המסומן בפועל לא תשחרר את הבחירה (התנהגות ברירת
        // המחדל של SelectableRegion ב-Windows); לחיצה על חלק לא-מסומן מבטלת
        // כרגיל. הבחירה מנוהלת ע"י SelectionArea פר-קישור, לכן מחשבים את קטע
        // הבחירה ישירות מול הפסקה שעליה לחצו.
        shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
          final selected = _savedSelectedText;
          if (selected == null || selected.isEmpty) return false;
          final root = context.findRenderObject();
          if (root == null) return true; // סלחני
          return clickIsOnSelectionWithinArea(
                root: root,
                globalPosition: globalPosition,
                selectedText: selected,
              ) ??
              true; // לא הוכרע — סלחני
        },
        menuBuilder: (menuCtx, _) =>
            ContextMenuUtils.buildCommentaryContextMenu(
          context: menuCtx,
          link: link,
          openBookCallback: widget.openBookCallback,
          fontSize: widget.fontSize,
          savedSelectedText: _savedSelectedText,
          onCopySelected: () => ContextMenuUtils.copyFormattedText(
            context: menuCtx,
            savedSelectedText: _savedSelectedText,
            fontSize: widget.fontSize,
            link: _savedSelectedLink,
          ),
        ),
        child: GestureDetector(
          onTap: () {
            widget.openBookCallback(
              TextBookTab(
                book: TextBook(
                  title: utils.getTitleFromPath(link.path2),
                ),
                index: link.index2 - 1,
                openLeftPane:
                    (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            child: _buildHighlightedText(content, link),
          ),
        ),
      ),
    ));
  }

  Widget _buildHighlightedText(String content, Link link) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        // חיפוש בתוכן - בדיקה אם הקישור הזה מכיל תוצאות
        String searchText = '';
        if (_searchQuery.isNotEmpty && _searchInContent) {
          final instanceKey = buildSelectedLinkInstanceKey(link);
          if (_linksWithSearchResults.contains(instanceKey)) {
            searchText = _searchQuery;
          }
        }

        return FutureBuilder<bool>(
          future: _resolveRemoveNikudForLink(link, settingsState),
          builder: (context, snapshot) {
            // מעבירים HTML גולמי ל-SmartTextWidget (כמו במפרשים) כדי ש-<br>
            // ומבני HTML אחרים יעובדו; הסרת התגים מראש איבדה את מעברי השורה.
            return SmartTextWidget(
              text: content,
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

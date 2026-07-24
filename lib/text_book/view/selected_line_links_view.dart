import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';

@visibleForTesting
RenderSettings buildSelectedLinkRenderSettings({
  required SettingsState settingsState,
  required bool removeNikud,
  required String searchText,
  bool removePunctuation = false,
}) {
  return RenderSettings(
    removeNikud: removeNikud,
    removePunctuation: removePunctuation,
    removeTeamim: !settingsState.showTeamim,
    replaceHolyNames: settingsState.replaceHolyNames,
    searchText: searchText,
    fontSize: settingsState.commentatorsFontSize,
    fontFamily: settingsState.commentatorsFontFamily,
    fontWeight: settingsState.commentatorsFontBold ? FontWeight.bold : null,
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
  // זהות היעד (אישי/רשמי+קטגוריה) נכללת כדי שלא יתערבב תוכן בין שני קישורים
  // לאותה כותרת ואינדקס — אחד אישי ואחד רשמי.
  final target =
      '${link.targetIsUserBook ? 'u' : 'o'}_${link.targetCategoryId ?? ''}';
  return '${link.path2}_${link.index2}_$target';
}

@visibleForTesting
String buildSelectedLinkInstanceKey(Link link) {
  final target =
      '${link.targetIsUserBook ? 'u' : 'o'}_${link.targetCategoryId ?? ''}';
  return '${link.path2}_${link.index1}_${link.index2}_${link.index2End ?? ''}_${link.heRef}_${link.start}_${link.end}_${link.connectionType}_$target';
}

@visibleForTesting
String buildSelectedLinksSearchKey({
  required String searchQuery,
  required bool searchInContent,
  required List<Link> links,
  Set<String> selectedLinkTypes = const {},
}) {
  final linksSignature = links.map(buildSelectedLinkInstanceKey).join('|');
  // סדר יציב — Set.toString() אינו מבטיח סדר, ומפתח מתחלף היה מרענן לשווא.
  final typesSignature = (selectedLinkTypes.toList()..sort()).join(',');
  return '${searchQuery}_$searchInContent|$typesSignature|$linksSignature';
}

/// מפתחות צ׳יפי הסינון של [links], בסדר התצוגה. סוג בעל תווית משמעותית מקבל
/// צ׳יפ משלו; שאר הסוגים ([LinkTypes.eraGroupedTypes]) מקובצים לפי דור ספר
/// היעד. הסדר: סוגים ייעודיים (לפי [_typeChipOrder]) ואז דורות לפי סדר הדורות.
@visibleForTesting
List<String> buildLinkChipKeys(List<Link> links, {String? openBookTitle}) {
  final keys = <String>{};
  for (final link in links) {
    keys.addAll(
      CommentaryService.linkChipKeys(link, openBookTitle: openBookTitle),
    );
  }

  return keys.toList()..sort((a, b) {
    final eraA = CommentaryService.eraFromChipKey(a);
    final eraB = CommentaryService.eraFromChipKey(b);
    // דורות תמיד אחרי הסוגים הייעודיים.
    if ((eraA == null) != (eraB == null)) return eraA == null ? -1 : 1;
    if (eraA != null) return eraA.order.compareTo(eraB!.order);

    final indexA = _typeChipOrder.indexOf(a);
    final indexB = _typeChipOrder.indexOf(b);
    if (indexA != indexB) {
      if (indexA == -1) return 1;
      if (indexB == -1) return -1;
      return indexA.compareTo(indexB);
    }
    return a.compareTo(b);
  });
}

/// הבחירה האפקטיבית: רק מפתחות שקיימים בצ׳יפים. בחירה שאין לה אף צ׳יפ קיים
/// (הגדרה שנשמרה כשמפתחות הצ׳יפים היו אחרים) מוחזרת כריקה = הצג הכל.
@visibleForTesting
Set<String> effectiveSelectedLinkTypes({
  required Set<String> selectedTypes,
  required List<String> availableKeys,
}) {
  if (selectedTypes.isEmpty) return const {};
  final available = availableKeys.toSet();
  return selectedTypes.where(available.contains).toSet();
}

/// חתימת הכותרות שדורותיהן נטענו. גרסת המטמון נכללת כי אחרי `clearEraCache`
/// הכותרות זהות אך המטמון ריק, וטעינה מחדש נדרשת.
@visibleForTesting
String buildEraPreloadSignature(Set<String> titles) =>
    '${CommentaryService.eraCacheVersion}|${(titles.toList()..sort()).join('|')}';

/// קישורי ההפניה שמהם נבנים הצ׳יפים — כל קישורי חלון הקריאה, לא רק הנראים,
/// כדי ששורת הצ׳יפים לא תקפוץ בדפדוף והבחירה לא תתאפס.
@visibleForTesting
List<Link> chipSourceLinks(List<Link> links) => links
    .where(
      (link) =>
          !LinkTypes.isDependentTextLink(link.connectionType) &&
          link.start == null &&
          link.end == null,
    )
    .toList();

@visibleForTesting
const Key linkTypeChipsRowKey = Key('link_type_chips_row');

@visibleForTesting
const Key linkEraChipsRowKey = Key('link_era_chips_row');

/// מפתחות הצ׳יפים מפוצלים לשני צירי המיון: `types` (סוג הקישור) ו-`eras`
/// (דור המחבר). הסדר בתוך כל ציר נשמר כפי שהתקבל.
@visibleForTesting
({List<String> types, List<String> eras}) splitChipKeysByAxis(
  List<String> keys,
) {
  final types = <String>[];
  final eras = <String>[];
  for (final key in keys) {
    (LinkTypes.isEraKey(key) ? eras : types).add(key);
  }
  return (types: types, eras: eras);
}

/// הבחירה השמורה החדשה אחרי לחיצה על צ׳יפ. הצ׳יפים מציגים רק את הבחירה
/// האפקטיבית, ולכן מחילים את הדלתא על הבחירה השמורה המלאה — אחרת כל מפתח
/// שאינו קיים כרגע היה נמחק.
@visibleForTesting
Set<String> applyChipSelectionDelta({
  required Set<String> savedTypes,
  required Set<String> effectiveTypes,
  required Set<String> newSelection,
}) {
  final added = newSelection.difference(effectiveTypes);
  final removed = effectiveTypes.difference(newSelection);
  return savedTypes.union(added).difference(removed);
}

/// סדר הצ׳יפים של הסוגים הייעודיים. סוג שאינו כאן מוצג אחריהם, אלפביתית.
const List<String> _typeChipOrder = [
  // SOURCE הוא ספר הבסיס שממנו נפתח המפרש — המידע הישיר ביותר לקטע הנלמד.
  LinkTypes.source,
  LinkTypes.einMishpat,
  LinkTypes.sifreiMitsvot,
  LinkTypes.mesoratHashas,
  LinkTypes.mishnahInTalmud,
  LinkTypes.quotation,
  LinkTypes.law,
  LinkTypes.liturgy,
  LinkTypes.summary,
  LinkTypes.footnotes,
  LinkTypes.allusion,
  LinkTypes.altToc,
  // אחרון שבסוגים — חוצץ בין הסוגים הייעודיים לצ׳יפי הדורות שאחריהם.
  LinkTypes.onBookKey,
];

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
  final Map<String, bool> _expanded = {};
  bool _searchInContent = false;
  Future<List<Link>>? _filteredLinksFuture;
  String _lastSearchKey = '';
  final Set<String> _linksWithSearchResults = {}; // קישורים עם תוצאות חיפוש
  String? _savedSelectedText; // טקסט נבחר לתפריט הקשר
  Link? _savedSelectedLink; // ה-link שממנו נבחר הטקסט
  final Object _selectionOwner = Object();
  int _selectionRevision = 0;
  String _preloadedEraTitles = '';
  int _eraGeneration = 0;
  List<Link>? _cachedChipLinksSource;
  String? _cachedChipCountsBookTitle;
  int _cachedChipCountsEraGeneration = -1;
  List<String> _cachedChipKeys = const [];

  @override
  void initState() {
    super.initState();
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
  }

  @override
  void dispose() {
    widget.selectionSyncController?.removeListener(
      _handleExternalSelectionChange,
    );
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SelectedLineLinksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController?.removeListener(
        _handleExternalSelectionChange,
      );
      widget.selectionSyncController?.addListener(
        _handleExternalSelectionChange,
      );
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
            !identical(previous.links, current.links) ||
            previous.selectedLinkTypes != current.selectedLinkTypes ||
            previous.fontSize != current.fontSize ||
            previous.removeNikud != current.removeNikud ||
            previous.removePunctuation != current.removePunctuation;
      },
      builder: (context, state) {
        final links = _referenceLinks(state);
        final openBookTitle = state.book.title;
        final chipKeys = _chipKeysFor(state.links, openBookTitle);
        final effectiveTypes = effectiveSelectedLinkTypes(
          selectedTypes: state.selectedLinkTypes,
          availableKeys: chipKeys,
        );
        final chipAxes = splitChipKeysByAxis(chipKeys);
        String chipLabel(String key) =>
            CommentaryService.chipKeyLabel(key, openBookTitle: openBookTitle);
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
                        borderRadius: AppTokens.borderRadiusAll,
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
            if (chipKeys.length > 1) ...[
              if (chipAxes.types.isNotEmpty)
                _buildChipRow(
                  key: linkTypeChipsRowKey,
                  keys: chipAxes.types,
                  savedTypes: state.selectedLinkTypes,
                  effectiveTypes: effectiveTypes,
                  chipLabel: chipLabel,
                  background: AppSurfaces.linkTypeChipsRow(context),
                ),
              if (chipAxes.eras.isNotEmpty)
                _buildChipRow(
                  key: linkEraChipsRowKey,
                  keys: chipAxes.eras,
                  savedTypes: state.selectedLinkTypes,
                  effectiveTypes: effectiveTypes,
                  chipLabel: chipLabel,
                  background: AppSurfaces.linkEraChipsRow(context),
                ),
              const SizedBox(height: AppTokens.spaceSM),
            ],
            // תוכן הקישורים
            Expanded(
              child: _buildLinksList(links, effectiveTypes, openBookTitle),
            ),
          ],
        );
      },
    );
  }

  /// שורת צ׳יפים של ציר מיון אחד. הדלתא מחושבת מול הבחירה האפקטיבית של
  /// *השורה בלבד* — אחרת מפתחות הציר השני היו נחשבים כמי שהוסרו ונמחקים.
  Widget _buildChipRow({
    required List<String> keys,
    required Set<String> savedTypes,
    required Set<String> effectiveTypes,
    required String Function(String key) chipLabel,
    required Color background,
    required Key key,
  }) {
    final rowKeys = keys.toSet();
    final rowSelected = effectiveTypes.intersection(rowKeys);
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceSM,
        0,
        AppTokens.spaceSM,
        AppTokens.spaceXS,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppTokens.borderRadiusAll,
        ),
        child: FilterChipsSelector<String>(
          items: keys,
          selectedItems: rowSelected.toList(),
          wrapAlignment: WrapAlignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSM,
            vertical: AppTokens.spaceXS,
          ),
          labelBuilder: chipLabel,
          onSelectionChanged: (selected) => context.read<TextBookBloc>().add(
            UpdateLinkTypeFilter(
              applyChipSelectionDelta(
                savedTypes: savedTypes,
                effectiveTypes: rowSelected,
                newSelection: selected.toSet(),
              ),
            ),
          ),
          chipBuilder: (context, item, isSelected) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Chip(
                label: Text(chipLabel(item)),
                backgroundColor: isSelected
                    ? Theme.of(context).colorScheme.secondary
                    : null,
                labelStyle: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onSecondary
                      : null,
                  fontSize: 11,
                ),
                labelPadding: const EdgeInsets.all(0),
              ),
            );
          },
        ),
      ),
    );
  }

  /// קישורים מבוססי-תווים (inline) מוצגים רק בתוך הטקסט, לא ברשימה.
  /// `visibleLinks` כבר מסונן מקישורים תלויי-טקסט, ולכן אין כאן בדיקת סוג.
  List<Link> _referenceLinks(TextBookLoaded state) => state.visibleLinks
      .where((link) => link.start == null && link.end == null)
      .toList();

  /// צ׳יפי הסינון של כל קישורי החלון, ממומשים לפי זהות הרשימה. `copyWith`
  /// מעביר את `links` באותה הפניה בגלילה, ולכן זהות היא מפתח נכון וזול.
  List<String> _chipKeysFor(List<Link> stateLinks, String openBookTitle) {
    // התחממות מטמון הדורות משנה מפתחות צ׳יפים, ולכן היא חלק ממפתח המימוש.
    if (identical(_cachedChipLinksSource, stateLinks) &&
        _cachedChipCountsBookTitle == openBookTitle &&
        _cachedChipCountsEraGeneration == _eraGeneration) {
      return _cachedChipKeys;
    }

    final chipLinks = chipSourceLinks(stateLinks);
    _ensureErasPreloaded(chipLinks);
    _cachedChipLinksSource = stateLinks;
    _cachedChipCountsBookTitle = openBookTitle;
    _cachedChipCountsEraGeneration = _eraGeneration;
    _cachedChipKeys = buildLinkChipKeys(
      chipLinks,
      openBookTitle: openBookTitle,
    );
    return _cachedChipKeys;
  }

  /// מטמון הדורות נקרא סינכרונית ב-build; בלי טעינה מוקדמת כל הקישורים ייפלו
  /// לצ׳יפ "ספרים נוספים". הטעינה אסינכרונית ומרעננת את ה-build בסיומה.
  void _ensureErasPreloaded(List<Link> links) {
    final titles = links
        .where((link) => LinkTypes.isEraGroupedType(link.connectionType))
        .map((link) => utils.getTitleFromPath(link.path2))
        .toSet();
    if (titles.isEmpty) return;

    final signature = buildEraPreloadSignature(titles);
    if (_preloadedEraTitles == signature) return;
    _preloadedEraTitles = signature;

    CommentaryService.preloadEras(titles).then((_) {
      // בחירת שורה מהירה מייתרת טעינה קודמת — rebuild מיותר.
      if (mounted && _preloadedEraTitles == signature) {
        setState(() => _eraGeneration++);
      }
    });
  }

  Widget _buildLinksList(
    List<Link> links,
    Set<String> selectedTypes,
    String? openBookTitle,
  ) {
    if (links.isEmpty) {
      return _buildEmptyMessage('לא נמצאו קישורים לקטע הנבחר');
    }

    // קבוצה ריקה = הצג הכל. כמה צ׳יפים נבחרים = איחוד, ולכן די בחיתוך אחד.
    final typeFilteredLinks = selectedTypes.isEmpty
        ? links
        : links
              .where(
                (link) => CommentaryService.linkChipKeys(
                  link,
                  openBookTitle: openBookTitle,
                ).any(selectedTypes.contains),
              )
              .toList();

    // הצ׳יפים נבנים מקישורי כל חלון הקריאה בעוד הרשימה מציגה את הקטע הנראה
    // בלבד, ולכן צ׳יפ שנבחר עשוי לא להתאים לאף קישור כאן.
    if (typeFilteredLinks.isEmpty) {
      return _buildEmptyMessage('לא נמצאו קישורים מהסוגים שנבחרו');
    }

    // יצירת מפתח ייחודי לחיפוש
    final searchKey = buildSelectedLinksSearchKey(
      searchQuery: _searchQuery,
      searchInContent: _searchInContent,
      links: typeFilteredLinks,
      selectedLinkTypes: selectedTypes,
    );

    // יצירת Future חדש רק אם החיפוש השתנה
    if (_lastSearchKey != searchKey) {
      _lastSearchKey = searchKey;
      _filteredLinksFuture = _filterLinksAsync(typeFilteredLinks);
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: AppFutureBuilder<List<Link>>(
        future: _filteredLinksFuture,
        builder: (context, data) {
          final filteredLinks = data;
          if (filteredLinks.isEmpty) {
            return _buildEmptyMessage('לא נמצאו קישורים התואמים לחיפוש');
          }

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

  Widget _buildEmptyMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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

  Widget _buildExpansionTile(Link link) {
    final instanceKey = buildSelectedLinkInstanceKey(link);
    final contentKey = buildSelectedLinkContentKey(link);
    final restoredExpanded =
        PageStorage.maybeOf(context)?.readState(
              context,
              identifier: instanceKey,
            )
            as bool?;
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
              fontVariations: AppFonts.boldFontVariations(
                settingsState.commentatorsFontFamily,
              ),
              fontFamily: settingsState.commentatorsFontFamily,
            ),
          );
        },
      ),
      subtitle: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          // קישור עם עוגן-מילה: אות הסימון שבגוף הטקסט מוצגת לפני ההפניה.
          var markerPrefix = '';
          if (link.anchorStart != null) {
            final markerLetter = anchorMarkerLetter(link);
            if (markerLetter != null) markerPrefix = '($markerLetter) ';
          }
          final rawFallback = settingsState.replaceHolyNames
              ? utils.replaceHolyNames(link.fallbackDisplayReference)
              : link.fallbackDisplayReference;

          if (!isExpanded) {
            return Text(
              markerPrefix + rawFallback,
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
            initialData: rawFallback,
            builder: (context, snapshot) {
              String displaySubtitle =
                  markerPrefix + (snapshot.data ?? rawFallback);
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
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

    // יירוט Ctrl+C ממוקם *מעל* ה-SelectionArea — שם מנגנון ה-override של
    // CopySelectionTextIntent מאתר אותו (מתחתיו הוא נשאר בלתי-נראה).
    return SelectionCopyShortcuts(
      onCopy: () => ContextMenuUtils.copyFormattedText(
        context: context,
        savedSelectedText: _savedSelectedText,
        fontSize: widget.fontSize,
        link: _savedSelectedLink,
      ),
      child: RtlSelectionShortcuts(
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
            } else if (selection == null ||
                selection.plainText.trim().isEmpty) {
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
              onTap: () async {
                final tab = await buildLinkTargetTab(link);
                if (!mounted) return;
                widget.openBookCallback(tab);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                child: _buildHighlightedText(content, link),
              ),
            ),
          ),
        ),
      ),
    );
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

        // מצב הניקוד/פיסוק של הטאב חל גם על תוכן הקישורים.
        final blocState = context.read<TextBookBloc>().state;
        final loaded = blocState is TextBookLoaded ? blocState : null;
        // מעבירים HTML גולמי ל-SmartTextWidget (כמו במפרשים) כדי ש-<br>
        // ומבני HTML אחרים יעובדו; הסרת התגים מראש איבדה את מעברי השורה.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SmartTextWidget(
              text: content,
              settings: buildSelectedLinkRenderSettings(
                settingsState: settingsState,
                removeNikud: loaded?.removeNikud ?? false,
                removePunctuation: loaded?.removePunctuation ?? false,
                searchText: searchText,
              ),
            ),
            LaazCommentarySubBlock(link: link),
          ],
        );
      },
    );
  }
}

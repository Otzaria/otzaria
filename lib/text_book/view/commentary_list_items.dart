part of 'commentary_list_base.dart';

/// כותרת קבוצת מפרשים ברשימה השטוחה — לחיצה מרחיבה/מכווצת דרך ההורה,
/// בלי להפריע לבחירת טקסט והעתקה (במקום ExpansionTile).
class _CommentaryGroupHeader extends StatelessWidget {
  final String bookTitle;
  final double fontSize;
  final bool isExpanded;
  final VoidCallback onTap;

  const _CommentaryGroupHeader({
    super.key,
    required this.bookTitle,
    required this.fontSize,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            ExpandingChevron(
              isExpanded: isExpanded,
              style: ExpandingChevronStyle.tree,
              size: 20,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  String displayTitle = bookTitle;
                  if (settingsState.replaceHolyNames) {
                    displayTitle = utils.replaceHolyNames(
                      displayTitle,
                      style: settingsState.holyNameStyle,
                    );
                  }
                  return Text(
                    displayTitle,
                    style: TextStyle(
                      fontSize: fontSize * 0.85,
                      fontWeight: FontWeight.bold,
                      fontVariations: AppFonts.boldFontVariations(
                        settingsState.commentatorsFontFamily,
                      ),
                      fontFamily: AppFonts.renderFontFamily(
                        settingsState.commentatorsFontFamily,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// קטע מפרש בודד ברשימה השטוחה. פריט עצמאי ברשימה — נבנה רק כשהוא נגלל
/// לתצוגה, כך שפתיחת קטע עם המון מפרשים אינה בונה את כולם בבת אחת.
class _CommentaryLinkItem extends StatefulWidget {
  final Link link;

  /// הפריט המוצג הקודם באותה קבוצה; כותרת זהה לשלו אינה מוצגת שוב (#4616).
  final Link? previousLink;
  final double fontSize;
  final Function(OpenedTab) openBookCallback;
  final TextDisplayProfile displayProfile;
  final TextDisplayProfile copyDisplayProfile;

  /// ציוני המפרשים מוצגים בגוף הספר — רק אז יש לאות הסימון מקבילה בטקסט.
  final bool showAnchorMarker;
  final bool showSearch;
  final ValueListenable<String> searchQueryListenable;
  final ValueListenable<int> currentSearchIndexListenable;
  final ValueListenable<int> totalSearchResultsListenable;
  final int Function(Link) getItemSearchIndex;
  final void Function(Link, int) updateSearchResultsCount;
  final void Function(Link, List<String>)? updateSearchSnippets;
  final Map<String, GlobalKey> itemKeys;
  final String Function(Link) getLinkKey;
  final Future<CommentaryCopyGuard?> Function() multiItemCopyGuard;
  final ValueListenable<String?> savedSelectedTextListenable;
  final ValueListenable<Link?> lastSelectedLinkListenable;

  /// הערות ספר המפרש, ממופתחות לפי שורה. אותו Future משותף לכל הקטעים.
  final Future<CommentaryNotesByLine> personalNotes;

  /// נקרא בלחיצת עכבר על פריט מפרש — לסימון המפרש הנבחר לייחוס העתקה.
  final void Function(Link link)? onLinkPointerDown;

  /// מדווח את הטקסט המרונדר של פריט מפרש — לשחזור מעברי שורה בהעתקה.
  final void Function(Link link, String renderedPlainText)? onLinkRendered;

  /// מדווח את כותרת הפריט המרונדרת (displayReference) — לשחזור מעברי שורה.
  final void Function(Link link, String renderedTitle)? onLinkTitleRendered;

  /// משחזר מעברי שורה בטקסט נבחר רב-שורתי (להעתקה מתפריט ההקשר).
  final String? Function(String?)? restoreLineBreaks;

  /// מחרוזת להדגשה מה-BLoC החיצוני, ללא שדה החיפוש הפנימי.
  final ValueListenable<String>? highlightQueryListenable;
  final void Function(Link link, int lineNumber)? onOpenPersonalNote;

  /// מכריע אם להציג את כותרת המקור (מקבל את הכותרת ללא אות העוגן).
  /// null = הצג תמיד.
  final bool Function(String displayTitle)? shouldShowItemTitle;

  const _CommentaryLinkItem({
    super.key,
    required this.link,
    this.previousLink,
    required this.fontSize,
    required this.openBookCallback,
    required this.displayProfile,
    required this.copyDisplayProfile,
    required this.showAnchorMarker,
    required this.showSearch,
    required this.searchQueryListenable,
    required this.currentSearchIndexListenable,
    required this.totalSearchResultsListenable,
    required this.getItemSearchIndex,
    required this.updateSearchResultsCount,
    this.updateSearchSnippets,
    required this.itemKeys,
    required this.getLinkKey,
    required this.multiItemCopyGuard,
    required this.savedSelectedTextListenable,
    required this.lastSelectedLinkListenable,
    required this.personalNotes,
    this.onLinkPointerDown,
    this.onLinkRendered,
    this.onLinkTitleRendered,
    this.restoreLineBreaks,
    this.highlightQueryListenable,
    this.onOpenPersonalNote,
    this.shouldShowItemTitle,
  });

  @override
  State<_CommentaryLinkItem> createState() => _CommentaryLinkItemState();
}

class _CommentaryLinkItemState extends State<_CommentaryLinkItem> {
  Future<void> _copySelection(
    BuildContext menuContext,
    String? savedText,
    Link link, {
    bool removeNikud = false,
  }) async {
    final guard = await widget.multiItemCopyGuard();
    if (!menuContext.mounted) return;
    await ContextMenuUtils.copyFormattedText(
      context: menuContext,
      savedSelectedText: _restoreLineBreaks(savedText),
      fontSize: widget.fontSize,
      link: link,
      removeNikud: removeNikud,
      protection: guard?.protection,
      segmentCount: guard?.segmentCount,
    );
  }

  /// פריטי התוספים בהקשרי המפרש. עם סימון — על המפרש המסומן, כמו בהעתקה.
  List<AppContextMenuEntry> _pluginEntries(
    BuildContext menuContext,
    String? selectedText,
  ) {
    if (!hasPluginContextMenuItems) return const [];
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return const [];
    final text = _restoreLineBreaks(selectedText) ?? '';
    final link = text.trim().isEmpty
        ? widget.link
        : widget.lastSelectedLinkListenable.value ?? widget.link;
    return buildCommentaryPluginMenuEntries(
      target: commentaryTargetForLink(link),
      mainBook: (
        book: state.book,
        currentRef: state.currentTitle,
        sectionIndex: link.index1 - 1,
        pageNumber: null,
      ),
      selectedText: text,
      // בחירה החוצה כמה מפרשים כפופה למגבלה המחמירה שביניהם, כמו בהעתקה.
      copyGuard: () async =>
          await widget.multiItemCopyGuard() ??
          (
            protection: await BookProtectionRepository.instance.forLink(link),
            segmentCount: countTextSegments(text),
          ),
      menuContext: menuContext,
      readerState: state,
    );
  }

  String? _restoreLineBreaks(String? text) =>
      (widget.restoreLineBreaks ?? (s) => s)(text);

  /// פותח את יעד הקישור בכרטיסייה חדשה (טקסט או PDF, לפי תבנית הפתיחה).
  Future<void> _navigateToLink(Link link) async {
    final tab = await buildLinkTargetTab(link);
    if (!mounted) return;
    widget.openBookCallback(tab);
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final Widget itemContent = ValueListenableBuilder<String?>(
      valueListenable: widget.savedSelectedTextListenable,
      child: Padding(
        key: widget.itemKeys[widget.getLinkKey(link)],
        padding: const EdgeInsetsDirectional.only(
          start: 32.0,
          end: 16.0,
          bottom: 8.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                final previousLink = widget.previousLink;
                return FutureBuilder<String>(
                  future: previousLink?.displayReference,
                  builder: (context, previousSnapshot) => FutureBuilder<String>(
                    future: link.displayReference,
                    builder: (context, snapshot) {
                      String displayTitle =
                          snapshot.data ?? link.fallbackDisplayReference;
                      final repeatsPrevious =
                          previousLink != null &&
                          displayTitle ==
                              (previousSnapshot.data ??
                                  previousLink.fallbackDisplayReference);
                      final showTitle =
                          !repeatsPrevious &&
                          (widget.shouldShowItemTitle?.call(displayTitle) ??
                              true);
                      // קישור עם עוגן-מילה: אות הסימון שמופיעה בגוף הטקסט
                      // נשמרת גם כשהכותרת מוסתרת — היא הקישור הוויזואלי להערה.
                      final markerText =
                          widget.showAnchorMarker && link.anchorStart != null
                          ? anchorMarkerText(link)
                          : null;
                      if (!showTitle && markerText == null) {
                        // דיווח ריק דורס כותרת שדווחה קודם — לשחזור העתקה נכון.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          widget.onLinkTitleRendered?.call(link, '');
                        });
                        return const SizedBox.shrink();
                      }
                      if (!showTitle) {
                        displayTitle = markerText!;
                      } else if (markerText != null) {
                        displayTitle = '$markerText $displayTitle';
                      }
                      if (settingsState.replaceHolyNames) {
                        displayTitle = utils.replaceHolyNames(
                          displayTitle,
                          style: settingsState.holyNameStyle,
                        );
                      }
                      final reportedTitle = displayTitle;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        widget.onLinkTitleRendered?.call(link, reportedTitle);
                      });
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                        child: Text(
                          displayTitle,
                          style: TextStyle(
                            fontSize: widget.fontSize * 0.75,
                            fontWeight: FontWeight.normal,
                            fontFamily: AppFonts.renderFontFamily(
                              settingsState.commentatorsFontFamily,
                            ),
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: Listenable.merge([
                widget.searchQueryListenable,
                widget.currentSearchIndexListenable,
                widget.totalSearchResultsListenable,
                if (widget.highlightQueryListenable != null)
                  widget.highlightQueryListenable!,
              ]),
              builder: (context, _) {
                // שדה החיפוש הפנימי גובר כשהוקלד בו; כשהוא ריק נופלים
                // להדגשת מונח החיפוש החיצוני (מתוצאה שנחתה בהערה).
                final internalQuery = widget.showSearch
                    ? widget.searchQueryListenable.value
                    : '';
                final searchQuery = internalQuery.isNotEmpty
                    ? internalQuery
                    : (widget.highlightQueryListenable?.value ?? '');
                final currentSearchIndex =
                    (widget.showSearch ||
                        widget.highlightQueryListenable != null)
                    ? widget.getItemSearchIndex(link)
                    : 0;
                return AppContextMenuRegion(
                  // ריחוף מקדים את טעינת קישורי קטע היעד, כדי שהתפריט
                  // ייבנה מוכן. הלחיצה מכסה מגע/עט, שאין בהם ריחוף.
                  onHoverEnter: () =>
                      TargetLineLinksService.instance.prefetchOnHover(link),
                  onSecondaryTapDown: (_) =>
                      TargetLineLinksService.instance.prefetch(link),
                  // לחיצה ימנית על הטקסט המסומן בפועל לא תשחרר את הבחירה
                  // (התנהגות ברירת המחדל של SelectableRegion ב-Windows);
                  // לחיצה על חלק לא-מסומן מבטלת כרגיל. אין כאן מעקב
                  // פר-שורה — הבחירה מנוהלת ע"י SelectionArea יחיד — לכן
                  // מחשבים את קטע הבחירה ישירות מול הפסקה שעליה לחצו.
                  shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                    final selected = widget.savedSelectedTextListenable.value;
                    if (selected == null || selected.isEmpty) {
                      return false;
                    }
                    final root = context.findRenderObject();
                    if (root == null) return true; // סלחני
                    return clickIsOnSelectionWithinArea(
                          root: root,
                          globalPosition: globalPosition,
                          selectedText: selected,
                        ) ??
                        true; // לא הוכרע — סלחני
                  },
                  menuBuilder: (menuCtx, _) {
                    final savedTextAtBuild = captureSelectedTextForMenu(
                      widget.savedSelectedTextListenable,
                    );
                    return ContextMenuUtils.buildCommentaryContextMenu(
                      context: menuCtx,
                      link: link,
                      openBookCallback: widget.openBookCallback,
                      fontSize: widget.fontSize,
                      displayProfile: widget.displayProfile,
                      copyDisplayProfile: widget.copyDisplayProfile,
                      savedSelectedText: savedTextAtBuild,
                      onNavigateToLink: _navigateToLink,
                      onCopySelected: () => _copySelection(
                        menuCtx,
                        savedTextAtBuild,
                        // במצב הפאנל/כרטיסייה אין מעקב פר-פריט אחר
                        // המפרש הנבחר (אין SelectionArea פר-פריט), לכן
                        // נופלים חזרה ל-link של הפריט שעליו נפתח התפריט.
                        widget.lastSelectedLinkListenable.value ?? link,
                      ),
                      onCopySelectedWithoutNikud: () => _copySelection(
                        menuCtx,
                        savedTextAtBuild,
                        widget.lastSelectedLinkListenable.value ?? link,
                        removeNikud: true,
                      ),
                    )..addAll(_pluginEntries(menuCtx, savedTextAtBuild));
                  },
                  child: CommentaryContent(
                    key: ValueKey(widget.getLinkKey(link)),
                    link: link,
                    fontSize: widget.fontSize,
                    openBookCallback: widget.openBookCallback,
                    displayProfile: widget.displayProfile,
                    searchQuery: searchQuery,
                    currentSearchIndex: currentSearchIndex,
                    onSearchResultsCountChanged:
                        (widget.showSearch ||
                            widget.highlightQueryListenable != null)
                        ? (count) =>
                              widget.updateSearchResultsCount(link, count)
                        : null,
                    onSearchSnippetsChanged:
                        widget.showSearch && widget.updateSearchSnippets != null
                        ? (snippets) =>
                              widget.updateSearchSnippets!(link, snippets)
                        : null,
                    onRendered: (text) =>
                        widget.onLinkRendered?.call(link, text),
                    personalNotes: widget.personalNotes,
                    onOpenPersonalNote: widget.onOpenPersonalNote,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      builder: (context, selectedText, child) => child!,
    );

    // הרשימה כולה עטופה ב-SelectionArea יחיד (בפאנל/בכרטיסייה/בתצוגה
    // המשולבת), ולכן מחזירים את התוכן ישירות — בלי SelectionArea
    // פר-פריט (שהיה הופך כל פריט ל"בלוק אטום" בבחירת מקלדת). עוטפים
    // ב-Listener שקוף כדי לזהות על איזה מפרש לחץ המשתמש (לייחוס בהעתקת
    // מקלדת Ctrl+C, שאין לה פריט-יעד).
    return Listener(
      onPointerDown: (_) => widget.onLinkPointerDown?.call(link),
      child: itemContent,
    );
  }
}

/// עוגני הקישורים של שורה [lineIndex] בספר, בסדר שה-href של הסמנים מפנה אליו.
List<Link> _bookAnchorLinksAt(TextBookLoaded state, int lineIndex) =>
    (state.linksByLine[lineIndex + 1] ?? const <Link>[])
        .where((link) => link.anchorStart != null)
        .toList();

/// גוף ההערה [note] של שורה [lineIndex] עם חלקי עוגני השורה שבו, כמו בגוף הספר.
@visibleForTesting
String noteBodyWithAnchors(
  TextBookLoaded state,
  int lineIndex,
  int note,
  String body,
) {
  if (!state.bodyDisplayProfile.showAnchorMarkers ||
      state.book.versionTitle != null) {
    return body;
  }
  final anchorLinks = _bookAnchorLinksAt(state, lineIndex);
  if (anchorLinks.isEmpty) return body;
  return injectLinkAnchorMarkers(
    rawLine: body,
    anchorLinks: anchorLinks,
    styleIndexByCommentator: anchorStyleIndexByCommentator(anchorLinks),
    lineIndex: lineIndex,
    notes: state.bookNotes.notesAt(lineIndex),
    note: note,
  );
}

/// תצוגת המפרש הוירטואלי 'הערות' — מציגה את גוף ההערות ה-inline
/// (<i class="footnote">) של השורות הנבחרות כאילו היו רשימת מפרשים.
class _NotesCommentaryWidget extends StatefulWidget {
  final List<String> notes;

  /// מונח החיפוש של הרשימה — גם תוצאת חיפוש בספר שנחתה בהערה.
  final String searchQuery;

  /// הספר שבו נחפש [searchQuery], כשזה מונח החיפוש בספר: ההערות מודגשות
  /// בפרמטרים שלו (מקורב, אפשרויות, מרווח) כמו טקסט הספר.
  final TextBookLoaded? searchedBook;
  final double fontSize;

  /// אותו פרופיל כמו טקסט המפרשים — ההערות מוצגות כמפרש.
  final TextDisplayProfile displayProfile;
  final Function(OpenedTab) openBookCallback;

  /// מצב הספר הראשי — דרוש לדיווח על טעות (ההערות inline בתוכו).
  final TextBookLoaded state;

  /// אינדקס השורה שאליה מיוחסות ההערות המוצגות — לדיווח הטעות.
  final int reportLineIndex;
  final List<int> reportLineIndexes;
  final SelectionSyncController? selectionSyncController;

  const _NotesCommentaryWidget({
    required this.notes,
    required this.searchQuery,
    required this.searchedBook,
    required this.fontSize,
    required this.displayProfile,
    required this.openBookCallback,
    required this.state,
    required this.reportLineIndex,
    required this.reportLineIndexes,
    this.selectionSyncController,
  });

  @override
  State<_NotesCommentaryWidget> createState() => _NotesCommentaryWidgetState();
}

class _NotesCommentaryWidgetState extends State<_NotesCommentaryWidget> {
  String? _selectedText;
  final Object _selectionOwner = Object();
  // onExit של ספאן מגיע גם אחרי שהווידג'ט הוסר מהעץ, וכבר אין context.
  late final AppWindowKeys _previewWindow;

  @override
  void initState() {
    super.initState();
    _previewWindow = AppWindowKeys.of(context);
  }

  void _onNotesSelectionChanged(String? text) {
    _selectedText = text;
    if (text != null && text.trim().isNotEmpty) {
      widget.selectionSyncController?.activate(
        _selectionOwner,
        selectionText: text,
        copyGuard: () async => (
          protection: widget.state.protection,
          segmentCount: countTextSegments(text),
        ),
      );
    } else {
      widget.selectionSyncController?.clear(_selectionOwner);
    }
  }

  @override
  void dispose() {
    widget.selectionSyncController?.clear(_selectionOwner);
    super.dispose();
  }

  /// הקישור של סמן `otzaria://anchor?ref=<line>_<i>` שבגוף הערה.
  Link? _anchorLink(String url) {
    final parts = Uri.tryParse(url)?.queryParameters['ref']?.split('_');
    if (parts == null || parts.length != 2) return null;
    final line = int.tryParse(parts[0]);
    final index = int.tryParse(parts[1]);
    if (line == null || index == null || index < 0) return null;
    final links = _bookAnchorLinksAt(widget.state, line);
    return index < links.length ? links[index] : null;
  }

  void _openAnchor(String url) {
    final link = _anchorLink(url);
    if (link == null) return;
    LinkPreviewOverlay.dismiss(window: _previewWindow);
    openLinkTarget(link, (tab) => widget.openBookCallback(tab));
  }

  void _previewAnchor(String url, Offset globalPosition) {
    final link = _anchorLink(url);
    if (link == null) return;
    LinkPreviewOverlay.cancelScheduledHide(AppWindowKeys.of(context));
    LinkPreviewOverlay.show(
      context,
      link: link,
      globalPosition: globalPosition,
      hoverMode: true,
      displayProfile: widget.displayProfile,
      onOpen: () => _openAnchor(url),
    );
  }

  /// ההערות הן טקסט הספר עצמו: בספר מוגן Ctrl+C עובר דרך מגבלת ההעתקה.
  Widget _notesCopyWrapper({required Widget child}) {
    final protection = widget.state.protection;
    final copy = !protection.isProtected
        ? SelectionCutFallthrough(child: child)
        : SelectionCopyShortcuts(
            onCopy: () => ContextMenuUtils.copyFormattedText(
              context: context,
              savedSelectedText: _selectedText,
              fontSize: widget.fontSize,
              protection: protection,
            ),
            child: child,
          );
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent ||
            !widget.state.book.isOfficialLibraryBook ||
            (_selectedText?.trim().isEmpty ?? true) ||
            DynamicShortcutRegistry.instance.match(event) != null) {
          return KeyEventResult.ignored;
        }
        final shortcut =
            ShortcutValidator.getShortcutValue(
              ShortcutValidator.reportErrorKey,
            ) ??
            '';
        if (shortcut.isEmpty ||
            !ShortcutHelper.matchesShortcut(event, shortcut)) {
          return KeyEventResult.ignored;
        }
        _reportError(context);
        return KeyEventResult.handled;
      },
      child: copy,
    );
  }

  Future<void> _reportError(BuildContext reportContext) {
    final selected = _selectedText ?? '';
    final target = bookNoteReportTarget(
      content: widget.state.content,
      bookNotes: widget.state.bookNotes,
      lineIndexes: widget.reportLineIndexes,
      selectedText: selected,
    );
    final lineIndex = target?.lineIndex ?? widget.reportLineIndex;
    final noteHtml = target?.singleNoteHtml;
    // A displayed word may match only the parent after punctuation is hidden.
    // Require an exact visible selection in the note as well as in its row.
    final useNoteContext =
        !widget.state.bookNotes.isEmpty ||
        noteHtml == null ||
        !buildCorrectionTemplate(noteHtml, selected).hasSelection ||
        lineIndex < 0 ||
        lineIndex >= widget.state.content.length ||
        !buildCorrectionTemplate(
          widget.state.content[lineIndex],
          selected,
        ).hasSelection;
    return ErrorReportHelper.showErrorReportDialog(
      context: reportContext,
      selectedText: selected,
      state: widget.state,
      fontSize: widget.fontSize,
      bookTitle: widget.state.book.title,
      savedSelectedIndex: lineIndex,
      // PR #4285: inline notes still belong to the exact source row. Only
      // line_note or an ambiguous inline selection uses frozen note context.
      reportContent: widget.state.bookNotes.isEmpty ? null : widget.notes,
      reportNote: useNoteContext ? target?.contextText ?? selected : null,
    );
  }

  /// מונח החיפוש בספר מודגש כמו בטקסט הספר; מונח משדה המפרשים — כמו במפרשים.
  RenderSettings _renderSettings(SettingsState settingsState) {
    final book = widget.searchedBook;
    return RenderSettings.fromProfile(
      widget.displayProfile,
      searchText: widget.searchQuery,
      currentSearchIndex: -1,
      searchOptions: book?.searchOptions ?? const {},
      alternativeWords: book?.alternativeWords ?? const {},
      spacingValues: book?.spacingValues ?? const {},
      isFuzzySearch: book?.searchMode == SearchMode.fuzzy,
      searchMode: book?.searchMode ?? SearchMode.exact,
      searchDistance: book?.searchDistance ?? 0,
      matchPolicy: book?.matchPolicy ?? SearchMatchPolicy.standard,
      isSearchResultLine:
          book?.lineParticipatesInSearchHighlight(widget.reportLineIndex) ??
          false,
      fontSize: widget.fontSize * 0.85,
      fontFamily: settingsState.commentatorsFontFamily,
      fontWeight: settingsState.commentatorsFontBold ? FontWeight.bold : null,
      lineHeight: settingsState.lineHeight,
      partialWordHighlight:
          book == null ||
          literalPartialWordMatch(
            widget.searchQuery,
            wholeWord: book.searchWholeWord,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final renderSettings = _renderSettings(settingsState);
        // SelectionArea משלו: הרשימה הזו מוחזרת *מחוץ* ל-SelectionArea של
        // רשימת המפרשים (שנבנה רק סביב ה-ListView), ולכן בלעדיו לא ניתן
        // לבחור טקסט בהערות כלל.
        return _notesCopyWrapper(
          child: RtlSelectionShortcuts(
            child: SelectionArea(
              // ביטול תפריט ברירת המחדל של Flutter — נשתמש ב-AppContextMenuRegion.
              contextMenuBuilder: (context, _) => const SizedBox.shrink(),
              onSelectionChanged: (selection) =>
                  _onNotesSelectionChanged(selection?.plainText),
              child: AppContextMenuRegion(
                // לחיצה ימנית על טקסט מסומן לא תשחרר את הבחירה (ברירת המחדל של
                // SelectableRegion ב-Windows); לחיצה מחוץ לבחירה מבטלת כרגיל.
                shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                  final selected = _selectedText;
                  if (selected == null || selected.isEmpty) return false;
                  final root = context.findRenderObject();
                  if (root == null) return true;
                  return clickIsOnSelectionWithinArea(
                        root: root,
                        globalPosition: globalPosition,
                        selectedText: selected,
                      ) ??
                      true;
                },
                menuBuilder: (menuCtx, _) => [
                  AppContextMenuEntry(
                    label: 'העתק',
                    icon: FluentIcons.copy_24_regular,
                    enabled:
                        _selectedText != null &&
                        _selectedText!.trim().isNotEmpty,
                    onTap: () => ContextMenuUtils.copyFormattedText(
                      context: menuCtx,
                      savedSelectedText: _selectedText,
                      fontSize: widget.fontSize,
                      protection: widget.state.protection,
                    ),
                  ),
                  if (showCopyWithoutNikud(_selectedText))
                    AppContextMenuEntry(
                      label: 'העתק בלי ניקוד',
                      icon: OtzariaIcons.alef_eraser_24_filled,
                      onTap: () => ContextMenuUtils.copyFormattedText(
                        context: menuCtx,
                        savedSelectedText: _selectedText,
                        fontSize: widget.fontSize,
                        removeNikud: true,
                        protection: widget.state.protection,
                      ),
                    ),
                  if (widget.state.book.isOfficialLibraryBook) ...[
                    const AppContextMenuEntry.divider(),
                    AppContextMenuEntry(
                      label: 'דווח על טעות בספר',
                      icon: FluentIcons.error_circle_24_regular,
                      enabled:
                          _selectedText != null &&
                          _selectedText!.trim().isNotEmpty,
                      onTap: () => _reportError(menuCtx),
                    ),
                  ],
                ],
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Text(
                          kNotesCommentatorTitle,
                          style: TextStyle(
                            fontSize: widget.fontSize * 0.85,
                            fontWeight: FontWeight.bold,
                            fontVariations: AppFonts.boldFontVariations(
                              settingsState.commentatorsFontFamily,
                            ),
                            fontFamily: AppFonts.renderFontFamily(
                              settingsState.commentatorsFontFamily,
                            ),
                          ),
                        ),
                      ),
                      ...widget.notes.map((note) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            right: 32.0,
                            left: 16.0,
                            bottom: 12.0,
                          ),
                          child: SmartTextWidget(
                            text: note,
                            settings: renderSettings,
                            onOpenBook: (tab) {
                              if (tab is TextBookTab) {
                                widget.openBookCallback(tab);
                              }
                            },
                            onAnchorTap: _openAnchor,
                            onAnchorHover: _previewAnchor,
                            onAnchorHoverExit: (_) =>
                                LinkPreviewOverlay.scheduleHide(_previewWindow),
                          ),
                        );
                      }),
                      const Divider(height: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

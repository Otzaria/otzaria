import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/progressive_scrolling.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/utils/copy_utils.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/utils/html_link_handler.dart';

class CombinedView extends StatefulWidget {
  CombinedView({
    super.key,
    required this.data,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    required this.textSize,
    required this.showCommentaryAsExpansionTiles,
    required this.tab,
  });

  final List<String> data;
  final Function(OpenedTab) openBookCallback;
  final void Function(int) openLeftPaneTab;
  final double textSize;
  final bool showCommentaryAsExpansionTiles;
  final TextBookTab tab;

  @override
  State<CombinedView> createState() => _CombinedViewState();
}

class _CombinedViewState extends State<CombinedView> {
  final GlobalKey<SelectionAreaState> _selectionKey =
      GlobalKey<SelectionAreaState>();

  // שמירת reference ל-BLoC לשימוש ב-listeners
  late final TextBookBloc _textBookBloc;

  @override
  void initState() {
    super.initState();
    // שמירת ה-BLoC מראש
    _textBookBloc = context.read<TextBookBloc>();

    // האזנה לשינויים במיקומי הפריטים כדי לאפס את הבחירה בגלילה
    widget.tab.positionsListener.itemPositions.addListener(_onScroll);
    // עדכון האינדקס ב-tab בזמן אמת
    widget.tab.positionsListener.itemPositions.addListener(_updateTabIndex);
  }

  @override
  void dispose() {
    widget.tab.positionsListener.itemPositions.removeListener(_onScroll);
    widget.tab.positionsListener.itemPositions.removeListener(_updateTabIndex);
    super.dispose();
  }

  // עדכון האינדקס הנוכחי ב-tab
  void _updateTabIndex() {
    final positions = widget.tab.positionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // שומר את האינדקס של הפריט הראשון הנראה
      widget.tab.index = positions.first.index;
    }
  }

  // פונקציה שתשלח אירוע איפוס ל-selectedIndex אם יש גלילה משמעותית
  void _onScroll() {
    // אנחנו רוצים את הלוגיקה הזו רק בתצוגה המפוצלת (SimpleBookView לשעבר)
    // שבה המפרשים מוצגים בפאנל צד (כלומר: לא ExpansionTiles)
    if (widget.showCommentaryAsExpansionTiles) return;

    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    final currentSelectedIndex = state.selectedIndex;

    if (currentSelectedIndex != null) {
      // אם האינדקס הנבחר כבר לא נראה (האינדקסים הנראים שונו עקב גלילה)
      final visibleIndices = state.visibleIndices;
      if (!visibleIndices.contains(currentSelectedIndex)) {
        _textBookBloc.add(const UpdateSelectedIndex(null));
      }
    }
  }

  // מעקב אחר בחירת טקסט בלי setState
  String? _selectedText;
  int? _selectionStart;
  int? _selectionEnd;

  // שמירת הבחירה האחרונה לשימוש בתפריט הקונטקסט
  String? _lastSelectedText;
  int? _lastSelectionStart;
  int? _lastSelectionEnd;

  // מעקב אחר האינדקס הנוכחי שנבחר
  int? _currentSelectedIndex;

  /// helper קטן שמחזיר רשימת MenuEntry מקבוצה אחת, כולל כפתור הצג/הסתר הכל
  List<ctx.MenuItem<void>> _buildGroup(
    String groupName,
    List<String>? group,
    TextBookLoaded st,
  ) {
    if (group == null || group.isEmpty) return const [];

    final bool groupActive =
        group.every((title) => st.activeCommentators.contains(title));

    return [
      ctx.MenuItem<void>(
        label: 'הצג את כל $groupName',
        icon: groupActive ? FluentIcons.checkmark_24_regular : null,
        onSelected: () {
          final current = List<String>.from(st.activeCommentators);
          if (groupActive) {
            current.removeWhere(group.contains);
          } else {
            for (final title in group) {
              if (!current.contains(title)) current.add(title);
            }
          }
          context.read<TextBookBloc>().add(UpdateCommentators(current));
        },
      ),
      ...group.map((title) {
        final bool isActive = st.activeCommentators.contains(title);
        return ctx.MenuItem<void>(
          label: title,
          icon: isActive ? FluentIcons.checkmark_24_regular : null,
          onSelected: () {
            final current = List<String>.from(st.activeCommentators);
            current.contains(title)
                ? current.remove(title)
                : current.add(title);
            context.read<TextBookBloc>().add(UpdateCommentators(current));
          },
        );
      }),
    ];
  }

  // בניית תפריט קונטקסט "מקובע" לאינדקס ספציפי של פסקה
  ctx.ContextMenu _buildContextMenuForIndex(
      TextBookLoaded state, int paragraphIndex) {
    // 1. קבלת מידע על גודל המסך
    final screenHeight = MediaQuery.of(context).size.height;

    // 2. זיהוי מפרשים שכבר שויכו לקבוצה
    final groups = state.commentatorGroups;
    final tanachGroup = CommentatorGroup.groupByTitle(groups, 'תורה שבכתב');
    final chazalGroup = CommentatorGroup.groupByTitle(groups, 'חז"ל');
    final rishonimGroup = CommentatorGroup.groupByTitle(groups, 'ראשונים');
    final acharonimGroup = CommentatorGroup.groupByTitle(groups, 'אחרונים');
    final modernGroup = CommentatorGroup.groupByTitle(groups, 'מחברי זמננו');
    final ungroupedGroup = CommentatorGroup.groupByTitle(groups, 'שאר מפרשים');

    // 3. יצירת רשימה של מפרשים שלא שויכו לאף קבוצה
    final List<String> ungrouped = ungroupedGroup.commentators;

    return ctx.ContextMenu(
      maxHeight: screenHeight * 0.9,
      entries: [
        ctx.MenuItem(
            label: 'חיפוש',
            icon: FluentIcons.search_24_regular,
            onSelected: () => widget.openLeftPaneTab(1)),
        ctx.MenuItem.submenu(
          label: 'מפרשים',
          icon: FluentIcons.book_24_regular,
          items: [
            ctx.MenuItem(
              label: 'הצג את כל המפרשים',
              icon: state.activeCommentators
                      .toSet()
                      .containsAll(state.availableCommentators)
                  ? FluentIcons.checkmark_24_regular
                  : null,
              onSelected: () {
                final allActive = state.activeCommentators
                    .toSet()
                    .containsAll(state.availableCommentators);
                context.read<TextBookBloc>().add(
                      UpdateCommentators(
                        allActive
                            ? <String>[]
                            : List<String>.from(state.availableCommentators),
                      ),
                    );
              },
            ),
            const ctx.MenuDivider(),
            ..._buildGroup(tanachGroup.title, tanachGroup.commentators, state),
            if (tanachGroup.commentators.isNotEmpty &&
                chazalGroup.commentators.isNotEmpty)
              const ctx.MenuDivider(),
            ..._buildGroup(chazalGroup.title, chazalGroup.commentators, state),
            if ((chazalGroup.commentators.isNotEmpty &&
                    rishonimGroup.commentators.isNotEmpty) ||
                (chazalGroup.commentators.isEmpty &&
                    tanachGroup.commentators.isNotEmpty &&
                    rishonimGroup.commentators.isNotEmpty))
              const ctx.MenuDivider(),
            ..._buildGroup(
                rishonimGroup.title, rishonimGroup.commentators, state),
            if ((rishonimGroup.commentators.isNotEmpty &&
                    acharonimGroup.commentators.isNotEmpty) ||
                (rishonimGroup.commentators.isEmpty &&
                    chazalGroup.commentators.isNotEmpty &&
                    acharonimGroup.commentators.isNotEmpty) ||
                (rishonimGroup.commentators.isEmpty &&
                    chazalGroup.commentators.isEmpty &&
                    tanachGroup.commentators.isNotEmpty &&
                    acharonimGroup.commentators.isNotEmpty))
              const ctx.MenuDivider(),
            ..._buildGroup(
                acharonimGroup.title, acharonimGroup.commentators, state),
            if ((acharonimGroup.commentators.isNotEmpty &&
                    modernGroup.commentators.isNotEmpty) ||
                (acharonimGroup.commentators.isEmpty &&
                    rishonimGroup.commentators.isNotEmpty &&
                    modernGroup.commentators.isNotEmpty) ||
                (acharonimGroup.commentators.isEmpty &&
                    rishonimGroup.commentators.isEmpty &&
                    chazalGroup.commentators.isNotEmpty &&
                    modernGroup.commentators.isNotEmpty) ||
                (acharonimGroup.commentators.isEmpty &&
                    rishonimGroup.commentators.isEmpty &&
                    chazalGroup.commentators.isEmpty &&
                    tanachGroup.commentators.isNotEmpty &&
                    modernGroup.commentators.isNotEmpty))
              const ctx.MenuDivider(),
            ..._buildGroup(modernGroup.title, modernGroup.commentators, state),
            if ((tanachGroup.commentators.isNotEmpty ||
                    chazalGroup.commentators.isNotEmpty ||
                    rishonimGroup.commentators.isNotEmpty ||
                    acharonimGroup.commentators.isNotEmpty ||
                    modernGroup.commentators.isNotEmpty) &&
                ungrouped.isNotEmpty)
              const ctx.MenuDivider(),
            ..._buildGroup(ungroupedGroup.title, ungrouped, state),
          ],
        ),
        ctx.MenuItem.submenu(
          label: 'קישורים',
          icon: FluentIcons.link_24_regular,
          enabled: state.visibleLinks.isNotEmpty,
          items: state.visibleLinks
              .map(
                (link) => ctx.MenuItem(
                  label: link.heRef,
                  onSelected: () {
                    widget.openBookCallback(
                      TextBookTab(
                        book: TextBook(
                          title: utils.getTitleFromPath(link.path2),
                        ),
                        index: link.index2 - 1,
                        openLeftPane:
                            (Settings.getValue<bool>('key-pin-sidebar') ??
                                    false) ||
                                (Settings.getValue<bool>(
                                        'key-default-sidebar-open') ??
                                    false),
                      ),
                    );
                  },
                ),
              )
              .toList(),
        ),
        const ctx.MenuDivider(),
        // הערות אישיות
        ctx.MenuItem(
          label: 'הוסף הערה אישית',
          icon: FluentIcons.note_add_24_regular,
          onSelected: () => _createNoteFromSelection(),
        ),
        const ctx.MenuDivider(),
        // העתקה
        ctx.MenuItem(
          label: 'העתק',
          icon: FluentIcons.copy_24_regular,
          enabled: (_lastSelectedText ?? _selectedText) != null &&
              (_lastSelectedText ?? _selectedText)!.trim().isNotEmpty,
          onSelected: _copyFormattedText,
        ),
        ctx.MenuItem(
          label: 'העתק את כל הפסקה',
          icon: FluentIcons.document_copy_24_regular,
          enabled: paragraphIndex >= 0 && paragraphIndex < widget.data.length,
          onSelected: () => _copyParagraphByIndex(paragraphIndex),
        ),
        ctx.MenuItem(
          label: 'העתק את הטקסט המוצג',
          icon: FluentIcons.copy_select_24_regular,
          onSelected: _copyVisibleText,
        ),
        const ctx.MenuDivider(),
        // Edit paragraph option
        ctx.MenuItem(
          label: 'ערוך פסקה זו',
          icon: FluentIcons.edit_24_regular,
          onSelected: () => _editParagraph(paragraphIndex),
        ),
      ],
    );
  }

  /// זיהוי האינדקס של הטקסט הנבחר
  int? _findIndexByText(String selectedText) {
    final cleanedSelected = selectedText.replaceAll(RegExp(r'\s+'), ' ').trim();

    for (int i = 0; i < widget.data.length; i++) {
      final originalData = widget.data[i];
      final cleanedOriginal = originalData
          .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (cleanedOriginal.contains(cleanedSelected) ||
          cleanedSelected.contains(cleanedOriginal)) {
        return i;
      }
    }
    return null;
  }

  /// יצירת הערה מטקסט נבחר
  void _createNoteFromSelection() {
    // נשתמש בבחירה האחרונה שנשמרה, או בבחירה הנוכחית
    final text = _lastSelectedText ?? _selectedText;
    if (text == null || text.trim().isEmpty) {
      UiSnack.show('אנא בחר טקסט ליצירת הערה אישית');
      return;
    }

    final start = _lastSelectionStart ?? _selectionStart ?? 0;
    final end = _lastSelectionEnd ?? _selectionEnd ?? text.length;
    _showNoteEditor(text, start, end);
  }

  /// העתקת פסקה לפי אינדקס (משתמש ב־widget.data[index] ומייצר גם HTML)
  Future<void> _copyParagraphByIndex(int index) async {
    if (index < 0 || index >= widget.data.length) return;

    final text = widget.data[index];
    if (text.trim().isEmpty) return;

    // קבלת ההגדרות הנוכחיות
    final settingsState = context.read<SettingsBloc>().state;
    final textBookState = context.read<TextBookBloc>().state;

    String finalText = text;
    String finalHtmlText = text;

    // אם צריך להוסיף כותרות
    if (settingsState.copyWithHeaders != 'none' &&
        textBookState is TextBookLoaded) {
      final bookName = CopyUtils.extractBookName(textBookState.book);
      final currentPath = await CopyUtils.extractCurrentPath(
        textBookState.book,
        index,
        bookContent: textBookState.content,
      );

      finalText = CopyUtils.formatTextWithHeaders(
        originalText: text,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );

      finalHtmlText = CopyUtils.formatTextWithHeaders(
        originalText: text,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );
    }

    final item = DataWriterItem();
    item.add(Formats.plainText(finalText));
    item.add(Formats.htmlText(_formatTextAsHtml(finalHtmlText)));

    await SystemClipboard.instance?.write([item]);
  }

  /// העתקת הטקסט המוצג במסך ללוח
  void _copyVisibleText() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded || state.visibleIndices.isEmpty) return;

    // איסוף כל הטקסט הנראה במסך
    final visibleTexts = <String>[];
    for (final index in state.visibleIndices) {
      if (index >= 0 && index < widget.data.length) {
        visibleTexts.add(widget.data[index]);
      }
    }

    if (visibleTexts.isEmpty) return;

    final combinedText = visibleTexts.join('\n\n');

    // קבלת ההגדרות הנוכחיות
    final settingsState = context.read<SettingsBloc>().state;

    String finalText = combinedText;

    // אם צריך להוסיף כותרות
    if (settingsState.copyWithHeaders != 'none') {
      final bookName = CopyUtils.extractBookName(state.book);
      final firstVisibleIndex = state.visibleIndices.first;
      final currentPath = await CopyUtils.extractCurrentPath(
        state.book,
        firstVisibleIndex,
        bookContent: state.content,
      );

      finalText = CopyUtils.formatTextWithHeaders(
        originalText: combinedText,
        copyWithHeaders: settingsState.copyWithHeaders,
        copyHeaderFormat: settingsState.copyHeaderFormat,
        bookName: bookName,
        currentPath: currentPath,
      );
    }

    final combinedHtml =
        finalText.split('\n\n').map(_formatTextAsHtml).join('<br><br>');

    final item = DataWriterItem();
    item.add(Formats.plainText(finalText));
    item.add(Formats.htmlText(combinedHtml));

    await SystemClipboard.instance?.write([item]);
  }

  /// עיצוב טקסט כ-HTML עם הגדרות הגופן הנוכחיות
  String _formatTextAsHtml(String text) {
    final settingsState = context.read<SettingsBloc>().state;
    // ממיר \n ל-<br> ב-HTML
    final textWithBreaks = text.replaceAll('\n', '<br>');
    return '''
<div style="font-family: ${settingsState.fontFamily}; font-size: ${widget.textSize}px; text-align: justify; direction: rtl;">
$textWithBreaks
</div>
''';
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  Future<void> _copyFormattedText() async {
    final plainText = _lastSelectedText ?? _selectedText;
    if (plainText == null || plainText.trim().isEmpty) {
      UiSnack.show('אנא בחר טקסט להעתקה');
      return;
    }

    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        // קבלת ההגדרות הנוכחיות לעיצוב
        final settingsState = context.read<SettingsBloc>().state;
        final textBookState = context.read<TextBookBloc>().state;

        // ניסיון למצוא את הטקסט המקורי עם תגי HTML
        String htmlContentToUse = plainText;

        // אם יש לנו אינדקס נוכחי, ננסה למצוא את הטקסט המקורי
        if (_currentSelectedIndex != null &&
            _currentSelectedIndex! >= 0 &&
            _currentSelectedIndex! < widget.data.length) {
          final originalData = widget.data[_currentSelectedIndex!];

          // בדיקה אם הטקסט הפשוט מופיע בטקסט המקורי
          final plainTextCleaned =
              plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
          final originalCleaned = originalData
              .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          // אם הטקסט הפשוט תואם לטקסט המקורי (או חלק ממנו), נשתמש במקורי
          if (originalCleaned.contains(plainTextCleaned) ||
              plainTextCleaned.contains(originalCleaned)) {
            htmlContentToUse = originalData;
          }
        }

        // הוספת כותרות אם נדרש
        String finalPlainText = plainText;
        if (settingsState.copyWithHeaders != 'none' &&
            textBookState is TextBookLoaded) {
          final bookName = CopyUtils.extractBookName(textBookState.book);
          final currentIndex = _currentSelectedIndex ?? 0;
          final currentPath = await CopyUtils.extractCurrentPath(
            textBookState.book,
            currentIndex,
            bookContent: textBookState.content,
          );

          finalPlainText = CopyUtils.formatTextWithHeaders(
            originalText: plainText,
            copyWithHeaders: settingsState.copyWithHeaders,
            copyHeaderFormat: settingsState.copyHeaderFormat,
            bookName: bookName,
            currentPath: currentPath,
          );

          // גם עדכון ה-HTML עם הכותרות
          htmlContentToUse = CopyUtils.formatTextWithHeaders(
            originalText: htmlContentToUse,
            copyWithHeaders: settingsState.copyWithHeaders,
            copyHeaderFormat: settingsState.copyHeaderFormat,
            bookName: bookName,
            currentPath: currentPath,
          );
        }

        // שימוש בפונקציית העזר החדשה להעתקה
        await CopyUtils.copyStyledToClipboard(
          plainText: finalPlainText,
          htmlText: htmlContentToUse,
          fontFamily: settingsState.fontFamily,
          fontSize: widget.textSize,
        );
      }
    } catch (e) {
      if (mounted) {
        UiSnack.showError('שגיאה בהעתקה מעוצבת: $e',
            backgroundColor: Theme.of(context).colorScheme.error);
      }
    }
  }

  /// הצגת עורך ההערות
  void _showNoteEditor(String selectedText, int charStart, int charEnd) {
    final controller = TextEditingController(text: selectedText.trim());

    showDialog(
      context: context,
      builder: (dialogContext) => PersonalNoteEditorDialog(
        title: 'הוסף הערה אישית',
        controller: controller,
      ),
    ).then((noteContent) async {
      if (noteContent == null) return;

      final trimmed = noteContent.trim();
      if (trimmed.isEmpty) {
        UiSnack.show('ההערה ריקה, לא נשמרה');
        return;
      }

      if (!mounted) return;

      try {
        // מציאת מספר השורה על בסיס האינדקס הנוכחי
        final lineNumber = (_currentSelectedIndex ?? 0) + 1;

        context.read<PersonalNotesBloc>().add(AddPersonalNote(
              bookId: widget.tab.book.title,
              lineNumber: lineNumber,
              content: trimmed,
            ));
        UiSnack.show('ההערה נשמרה בהצלחה');
        widget.openLeftPaneTab(2);
      } catch (e) {
        UiSnack.showError('שמירת ההערה נכשלה: $e');
      }
    });
  }

  Widget buildKeyboardListener() {
    return BlocBuilder<TextBookBloc, TextBookState>(
      bloc: context.read<TextBookBloc>(),
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return ProgressiveScroll(
          maxSpeed: 10000.0,
          curve: 10.0,
          accelerationFactor: 5,
          scrollController: widget.tab.mainOffsetController,
          child: SelectionArea(
            key: _selectionKey,
            contextMenuBuilder: (_, __) => const SizedBox.shrink(),
            onSelectionChanged: (selection) {
              final text = selection?.plainText ?? '';
              if (text.isEmpty) {
                _selectedText = null;
                _selectionStart = null;
                _selectionEnd = null;
                _currentSelectedIndex = null;
                // עדכון ה-BLoC שאין טקסט נבחר
                context
                    .read<TextBookBloc>()
                    .add(const UpdateSelectedTextForNote(null, null, null));
              } else {
                _selectedText = text;
                _selectionStart = 0;
                _selectionEnd = text.length;

                // ניסיון לזהות את האינדקס על בסיס התוכן
                _currentSelectedIndex = _findIndexByText(text);

                // שמירת הבחירה האחרונה
                _lastSelectedText = text;
                _lastSelectionStart = 0;
                _lastSelectionEnd = text.length;

                // עדכון ה-BLoC עם הטקסט הנבחר
                context
                    .read<TextBookBloc>()
                    .add(UpdateSelectedTextForNote(text, 0, text.length));
              }
              // בלי setState – כדי לא לרנדר את כל העץ תוך כדי גרירת הבחירה
            },
            // שים לב: אין כאן יותר ContextMenuRegion עוטף את כל הרשימה.
            child: buildOuterList(state),
          ),
        );
      },
    );
  }

  Widget buildOuterList(TextBookLoaded state) {
    return ScrollablePositionedList.builder(
      key: ValueKey('combined-${widget.tab.book.title}'),
      initialScrollIndex: widget.tab.index,
      itemPositionsListener: widget.tab.positionsListener,
      itemScrollController: widget.tab.scrollController,
      scrollOffsetController: widget.tab.mainOffsetController,
      itemCount: widget.data.length,
      itemBuilder: (context, index) {
        ExpansibleController controller = ExpansibleController();
        return buildExpansiomTile(controller, index, state);
      },
    );
  }

  Widget buildExpansiomTile(
    ExpansibleController controller,
    int index,
    TextBookLoaded state,
  ) {
    final isSelected = state.selectedIndex == index;
    final isHighlighted = state.highlightedLine == index;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isSelected && !controller.isExpanded) {
        controller.expand();
      } else if (!isSelected && controller.isExpanded) {
        controller.collapse();
      }
    });

    final theme = Theme.of(context);
    final backgroundColor = () {
      if (isHighlighted) {
        return theme.colorScheme.secondaryContainer.withValues(alpha: 0.4);
      }
      if (isSelected) {
        return theme.colorScheme.primary.withValues(alpha: 0.08);
      }
      return null;
    }();

    return ctx.ContextMenuRegion(
      contextMenu: _buildContextMenuForIndex(state, index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: backgroundColor != null
            ? BoxDecoration(color: backgroundColor)
            : null,
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: ExpansionTile(
            shape: const Border(),
            controller: controller,
            key: PageStorageKey(widget.data[index]),
            iconColor: Colors.transparent,
            tilePadding: const EdgeInsets.all(0.0),
            collapsedIconColor: Colors.transparent,
            // הסרת כל הצבעים והאפקטים מה-ExpansionTile - נשתמש רק ב-Container למעלה
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            // ביטול אפקטי hover ו-splash
            visualDensity: VisualDensity.compact,
            // הסרת onExpansionChanged - נטפל בלחיצות ידנית
            title: GestureDetector(
              // רק לחיצה על ה-title תפתח/תסגור את המפרשים
              onTap: () {
                if (controller.isExpanded) {
                  controller.collapse();
                  _textBookBloc.add(const UpdateSelectedIndex(null));
                } else {
                  controller.expand();
                  _textBookBloc.add(UpdateSelectedIndex(index));
                }
              },
              child: Padding(
                // padding קטן לעיצוב
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settingsState) {
                        String data = widget.data[index];
                        if (!settingsState.showTeamim) {
                          data = utils.removeTeamim(data);
                        }
                        if (settingsState.replaceHolyNames) {
                          data = utils.replaceHolyNames(data);
                        }

                        return HtmlWidget(
                          '''
                        <div style="text-align: justify; direction: rtl;">
                          ${() {
                            String processedData = state.removeNikud
                                ? utils.highLight(
                                    utils.removeVolwels('$data\n'),
                                    state.searchText)
                                : utils.highLight('$data\n', state.searchText);
                            // החלת עיצוב הסוגריים העגולים
                            return utils
                                .formatTextWithParentheses(processedData);
                          }()}
                        </div>
                        ''',
                          textStyle: TextStyle(
                            fontSize: widget.textSize,
                            fontFamily: settingsState.fontFamily,
                            height: 1.5,
                          ),
                          onTapUrl: settingsState.enableHtmlLinks
                              ? (url) async {
                                  return await HtmlLinkHandler.handleLink(
                                    context,
                                    url,
                                    (tab) => widget.openBookCallback(tab),
                                  );
                                }
                              : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            children: [
              if (widget.showCommentaryAsExpansionTiles)
                CommentaryListBase(
                  indexes: [index],
                  fontSize: widget.textSize,
                  openBookCallback: widget.openBookCallback,
                  showSearch: false,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildKeyboardListener();
  }

  /// Opens the text editor for a specific paragraph
  void _editParagraph(int paragraphIndex) {
    if (paragraphIndex >= 0 && paragraphIndex < widget.data.length) {
      context.read<TextBookBloc>().add(OpenEditor(index: paragraphIndex));
    }
  }
}

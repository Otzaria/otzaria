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
import 'package:otzaria/utils/text_with_inline_links.dart';

class CombinedView extends StatefulWidget {
  const CombinedView({
    super.key,
    required this.data,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    required this.textSize,
    required this.showCommentaryAsExpansionTiles,
    required this.tab,
    this.isPreviewMode = false,
    this.onOpenPersonalNotes,
    this.onOpenCommentatorsPane,
  });

  final List<String> data;
  final Function(OpenedTab) openBookCallback;
  final void Function(int) openLeftPaneTab;
  final double textSize;
  final bool showCommentaryAsExpansionTiles;
  final TextBookTab tab;
  final bool isPreviewMode;
  final VoidCallback? onOpenPersonalNotes;
  final VoidCallback? onOpenCommentatorsPane;

  @override
  State<CombinedView> createState() => _CombinedViewState();
}

class _CombinedViewState extends State<CombinedView> {
  // שמירת הטקסט הנבחר האחרון
  String? _savedSelectedText;
  // שמירת האינדקס של השורה שממנה הטקסט הודגש
  int? _savedSelectedIndex;

  // שמירת reference ל-BLoC לשימוש ב-listeners
  late final TextBookBloc _textBookBloc;

  bool _hasScrolledToInitialPosition = false;

  /// פתיחת חלון הצד של המפרשים רק אם מוסיפים מפרשים ומפרשים מוגדרים בצד הטקסט (לא מתחת)
  void _openCommentatorsPane({required bool isAdding}) {
    if (isAdding &&
        !widget.showCommentaryAsExpansionTiles &&
        widget.onOpenCommentatorsPane != null) {
      widget.onOpenCommentatorsPane!();
    }
  }

  late final FocusNode _focusNode;

  // שמירת גובה הבלוק בפועל לחישובים דינאמיים
  double _viewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    // שמירת ה-BLoC מראש
    _textBookBloc = context.read<TextBookBloc>();

    // האזנה לשינויים במיקומי הפריטים כדי לאפס את הבחירה בגלילה
    widget.tab.positionsListener.itemPositions.addListener(_onScroll);
    // עדכון האינדקס ב-tab בזמן אמת
    widget.tab.positionsListener.itemPositions.addListener(_updateTabIndex);

    // האזנה לשינויים ב-state כדי לגלול למיקום הנכון בפעם הראשונה
    _textBookBloc.stream.listen((state) {
      if (state is TextBookLoaded &&
          !_hasScrolledToInitialPosition &&
          state.visibleIndices.isNotEmpty) {
        _hasScrolledToInitialPosition = true;
        final initialIndex = state.visibleIndices.first;
        debugPrint('DEBUG: גלילה אוטומטית למיקום שמור: $initialIndex');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.tab.scrollController.isAttached) {
            widget.tab.scrollController.scrollTo(
              index: initialIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    widget.tab.positionsListener.itemPositions.removeListener(_onScroll);
    widget.tab.positionsListener.itemPositions.removeListener(_updateTabIndex);
    _focusNode.dispose();
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

  // מעקב אחר האינדקס הנוכחי שנבחר (לשימוש בהעתקה עם כותרות)
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
        label: Text('הצג את כל $groupName'),
        icon: groupActive ? const Icon(FluentIcons.checkmark_24_regular) : null,
        onSelected: (_) {
          final current = List<String>.from(st.activeCommentators);
          final isAdding = !groupActive;
          if (groupActive) {
            current.removeWhere(group.contains);
          } else {
            for (final title in group) {
              if (!current.contains(title)) current.add(title);
            }
          }
          context.read<TextBookBloc>().add(UpdateCommentators(current));
          _openCommentatorsPane(isAdding: isAdding);
        },
      ),
      ...group.map((title) {
        final bool isActive = st.activeCommentators.contains(title);
        return ctx.MenuItem<void>(
          label: Text(title),
          icon: isActive ? const Icon(FluentIcons.checkmark_24_regular) : null,
          onSelected: (_) {
            final current = List<String>.from(st.activeCommentators);
            final isAdding = !current.contains(title);
            current.contains(title)
                ? current.remove(title)
                : current.add(title);
            context.read<TextBookBloc>().add(UpdateCommentators(current));
            _openCommentatorsPane(isAdding: isAdding);
          },
        );
      }),
    ];
  }

  // בניית תפריט קונטקסט "מקובע" לאינדקס ספציפי של פסקה
  ctx.ContextMenu _buildContextMenuForIndex(
      TextBookLoaded state, int paragraphIndex, BuildContext menuContext) {
    // אם זה מצב תצוגה מקדימה, החזר תפריט מצומצם
    if (widget.isPreviewMode) {
      return ctx.ContextMenu(
        entries: [
          ctx.MenuItem(
            label: const Text('העתק'),
            icon: const Icon(FluentIcons.copy_24_regular),
            enabled: _savedSelectedText != null &&
                _savedSelectedText!.trim().isNotEmpty,
            onSelected: (_) => _copyFormattedText(),
          ),
        ],
      );
    }

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
            label: const Text('חיפוש'),
            icon: const Icon(FluentIcons.search_24_regular),
            onSelected: (_) => widget.openLeftPaneTab(1)),
        ctx.MenuItem.submenu(
          label: const Text('מפרשים'),
          icon: const Icon(FluentIcons.book_24_regular),
          enabled: state.availableCommentators.isNotEmpty,
          items: [
            ctx.MenuItem(
              label: const Text('הצג את כל המפרשים'),
              icon: state.activeCommentators
                      .toSet()
                      .containsAll(state.availableCommentators)
                  ? const Icon(FluentIcons.checkmark_24_regular)
                  : null,
              onSelected: (_) {
                final allActive = state.activeCommentators
                    .toSet()
                    .containsAll(state.availableCommentators);
                final isAdding = !allActive;
                context.read<TextBookBloc>().add(
                      UpdateCommentators(
                        allActive
                            ? <String>[]
                            : List<String>.from(state.availableCommentators),
                      ),
                    );
                _openCommentatorsPane(isAdding: isAdding);
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
          label: const Text('קישורים'),
          icon: const Icon(FluentIcons.link_24_regular),
          enabled: state.visibleLinks.isNotEmpty,
          items: state.visibleLinks
              .map(
                (link) => ctx.MenuItem(
                  label: Text(link.heRef),
                  onSelected: (_) {
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
          label: const Text('הוסף הערה אישית '),
          icon: const Icon(FluentIcons.note_add_24_regular),
          onSelected: (_) => _createNoteForCurrentLine(),
        ),
        const ctx.MenuDivider(),
        // העתקה
        ctx.MenuItem(
          label: const Text('העתק'),
          icon: const Icon(FluentIcons.copy_24_regular),
          enabled: _savedSelectedText != null &&
              _savedSelectedText!.trim().isNotEmpty,
          onSelected: (_) => _copyFormattedText(),
        ),
        ctx.MenuItem(
          label: const Text('העתק את כל הפסקה'),
          icon: const Icon(FluentIcons.document_copy_24_regular),
          enabled: paragraphIndex >= 0 && paragraphIndex < widget.data.length,
          onSelected: (_) => _copyParagraphByIndex(paragraphIndex),
        ),
        ctx.MenuItem(
          label: const Text('העתק את הטקסט המוצג'),
          icon: const Icon(FluentIcons.copy_select_24_regular),
          onSelected: (_) => _copyVisibleText(),
        ),
        const ctx.MenuDivider(),
        // Edit paragraph option
        ctx.MenuItem(
          label: const Text('ערוך פסקה זו'),
          icon: const Icon(FluentIcons.edit_24_regular),
          onSelected: (_) => _editParagraph(paragraphIndex),
        ),
      ],
    );
  }

  /// יצירת הערה לשורה הנוכחית
  void _createNoteForCurrentLine() {
    // לא צריך טקסט נבחר - ההערה חלה על כל השורה
    _showNoteEditor();
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
    // משתמש בטקסט השמור שנבחר לפני פתיחת התפריט
    final plainText = _savedSelectedText;

    debugPrint('_copyFormattedText called with: "$plainText"');
    debugPrint('_currentSelectedIndex: $_currentSelectedIndex');

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
  void _showNoteEditor() {
    final controller = TextEditingController();

    // שמירת ה-state הנוכחי לפני פתיחת הדיאלוג
    final state = _textBookBloc.state;
    if (state is! TextBookLoaded) return;

    // שמירת הטקסט הנבחר לפני פתיחת הדיאלוג
    final selectedText = _savedSelectedText;

    // משתמש בשורה שממנה הודגש טקסט (אם קיים), אחרת בשורה הנבחרת, אחרת בשורה הראשונה הנראית
    final currentIndex = _savedSelectedIndex ??
        state.selectedIndex ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

    // קבלת הטקסט המזהה של השורה - אם יש טקסט נבחר, משתמשים בו (אחרי הסרת ניקוד), אחרת בטקסט המזהה (כמו שיוצג ככותרת)
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? removeHebrewDiacritics(selectedText!.trim())
        : extractDisplayTextFromLines(
            state.content,
            currentIndex + 1,
            excludeBookTitle: widget.tab.book.title,
          );

    showDialog(
      context: context,
      builder: (dialogContext) => PersonalNoteEditorDialog(
        title: 'הוסף הערה',
        controller: controller,
        referenceText: referenceText,
        icon: FluentIcons.note_add_24_regular,
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
        // מציאת מספר השורה על בסיס האינדקס שנשמר
        final lineNumber = currentIndex + 1;

        context.read<PersonalNotesBloc>().add(AddPersonalNote(
              bookId: widget.tab.book.title,
              lineNumber: lineNumber,
              content: trimmed,
              selectedText: selectedText?.trim(),
            ));
        UiSnack.show('ההערה נשמרה בהצלחה');

        // פתיחת חלונית ההערות האישיות
        widget.onOpenPersonalNotes?.call();
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
        return LayoutBuilder(
          builder: (context, constraints) {
            // שומר את גובה הבלוק בפועל לשימוש בחישובי הגלילה
            _viewportHeight = constraints.maxHeight;

            return SelectionArea(
              // SelectionArea אחד לכל הרשימה - מאפשר בחירה רציפה בין פסקאות
              contextMenuBuilder: (context, selectableRegionState) {
                return const SizedBox.shrink();
              },
              onSelectionChanged: (selection) {
                if (selection != null && selection.plainText.isNotEmpty) {
                  // מחשב את מספר השורה המדויק של הטקסט המודגש
                  // משתמש באותה לוגיקה כמו בדיווח שגיאות
                  final state = _textBookBloc.state;
                  int? foundIndex;

                  if (state is TextBookLoaded) {
                    // מקבל את השורה הראשונה הנראית
                    final baseIndex = state.visibleIndices.isNotEmpty
                        ? state.visibleIndices.first
                        : 0;

                    // בונה את הטקסט הנראה
                    final visibleText = state.visibleIndices
                        .map((idx) =>
                            widget.data[idx].replaceAll(RegExp(r'<[^>]*>'), ''))
                        .join('\n');

                    // מוצא את המיקום של הטקסט המודגש
                    final selectionStart =
                        visibleText.indexOf(selection.plainText);

                    if (selectionStart >= 0) {
                      // סופר כמה שורות יש לפני הטקסט המודגש
                      final before = visibleText.substring(0, selectionStart);
                      final offset = '\n'.allMatches(before).length;
                      foundIndex = baseIndex + offset;
                    }
                  }

                  setState(() {
                    _savedSelectedText = selection.plainText;
                    _savedSelectedIndex = foundIndex;
                    _currentSelectedIndex = foundIndex;
                  });
                }
              },
              child: Directionality(
                textDirection: widget.isPreviewMode
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                child: ScrollConfiguration(
                  // מונע בעיות של Scrollbar עם ScrollController לא מחובר
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                  ),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: ProgressiveScroll(
                      focusNode: _focusNode,
                      maxSpeed: 10000.0,
                      curve: 10.0,
                      accelerationFactor: 5,
                      scrollController: widget.tab.mainOffsetController,
                      child: buildOuterList(state),
                    ),
                  ),
                ),
              ),
            );
          },
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

    return Column(
      key: PageStorageKey(widget.data[index]),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // הטקסט של הספר - ללא SelectionArea נפרד, כי יש SelectionArea כללי
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: backgroundColor != null
              ? BoxDecoration(color: backgroundColor)
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _focusNode.requestFocus();
              // מאפס את הטקסט השמור כשלוחצים על הפסקה
              setState(() {
                _savedSelectedText = null;
                _currentSelectedIndex = null;
              });
              // פשוט מעדכן את selectedIndex - זה יגרום לבנייה מחדש
              if (isSelected) {
                _textBookBloc.add(const UpdateSelectedIndex(null));
              } else {
                _textBookBloc.add(UpdateSelectedIndex(index));

                // גלילה אוטומטית כך שהקטע יהיה בראש העמוד
                // רק אם יש מפרשים להצגה ואנחנו במצב ExpansionTiles
                if (widget.showCommentaryAsExpansionTiles &&
                    _hasCommentaries(state, index)) {
                  // מחכים שה-UI יתעדכן עם פתיחת המפרש, ואז קופצים למיקום
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted && widget.tab.scrollController.isAttached) {
                        // גלילה חכמה: נגלול כך שהטקסט הבא (index + 1) יהיה בתחתית
                        // המפרשים תופסים עד 75% מהבלוק
                        // נרצה שהטקסט הבא יהיה ב-90% מהבלוק (כלומר 10% מלמטה)
                        // כך נוודא שרואים: 15% טקסט למעלה, 75% מפרשים, 10% טקסט למטה
                        final nextIndex =
                            (index + 1).clamp(0, widget.data.length - 1);
                        widget.tab.scrollController.scrollTo(
                          index: nextIndex,
                          alignment:
                              0.9, // הטקסט הבא יהיה ב-90% מלמעלה (כלומר 10% מלמטה)
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    });
                  });
                }
              }
            },
            onSecondaryTapDown: (details) {
              // שומר את האינדקס הנוכחי לשימוש בתפריט ההקשר
              setState(() {
                _currentSelectedIndex = index;
              });
            },
            child: ctx.ContextMenuRegion(
              contextMenu: _buildContextMenuForIndex(state, index, context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settingsState) {
                        var textMaxWidth = settingsState.textMaxWidth;

                        // אם הערך שלילי, זו רמה שצריך לחשב לפי גודל המסך
                        // למשל -2 = רמה 2 = 90% מרוחב המסך
                        if (textMaxWidth < 0) {
                          final level = (-textMaxWidth).toInt();
                          final widthPercent = 1.0 - (level * 0.05);
                          textMaxWidth = constraints.maxWidth * widthPercent;
                        }

                        String data = widget.data[index];

                        // הוספת קישורים מבוססי תווים לפני כל עיבוד אחר
                        // כי start/end מתייחסים לטקסט המקורי
                        String dataWithLinks = data;
                        if (settingsState.enableHtmlLinks) {
                          try {
                            final linksForLine = state.links
                                .where((link) =>
                                    link.index1 == index + 1 &&
                                    link.start != null &&
                                    link.end != null)
                                .toList();

                            if (linksForLine.isNotEmpty) {
                              dataWithLinks =
                                  addInlineLinksToText(data, linksForLine);
                            }
                          } catch (e) {
                            // אם יש שגיאה, פשוט נשתמש בטקסט המקורי
                            dataWithLinks = data;
                          }
                        }

                        // עיבודים נוספים
                        if (!settingsState.showTeamim) {
                          dataWithLinks = utils.removeTeamim(dataWithLinks);
                        }
                        if (settingsState.replaceHolyNames) {
                          dataWithLinks = utils.replaceHolyNames(dataWithLinks);
                        }

                        String processedData = state.removeNikud
                            ? utils.highLight(
                                utils.removeVolwels('$dataWithLinks\n'),
                                state.searchText)
                            : utils.highLight(
                                '$dataWithLinks\n', state.searchText);

                        processedData =
                            utils.formatTextWithParentheses(processedData);

                        final textWidget = HtmlWidget(
                          '''
                          <div style="text-align: justify; direction: rtl;">
                            $processedData
                          </div>
                          ''',
                          key: ValueKey('html_${widget.tab.book.title}_$index'),
                          textStyle: TextStyle(
                            fontSize: widget.textSize,
                            fontFamily: settingsState.fontFamily,
                            height: 1.5,
                          ),
                          onTapUrl: (url) async {
                            return await HtmlLinkHandler.handleLink(
                              context,
                              url,
                              (tab) => widget.openBookCallback(tab),
                            );
                          },
                        );

                        // אם textMaxWidth הוא 0, הטקסט ימלא את כל הרוחב
                        // אחרת, הטקסט יהיה ממורכז עם רוחב מקסימלי
                        if (textMaxWidth > 0) {
                          return Center(
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxWidth: textMaxWidth),
                              child: textWidget,
                            ),
                          );
                        }
                        return textWidget;
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        // המפרשים - ללא SelectionArea נפרד, כי יש SelectionArea כללי
        if (widget.showCommentaryAsExpansionTiles &&
            isSelected &&
            _hasCommentaries(state, index))
          _CommentaryCard(
            key: ValueKey('commentary_card_$index'),
            index: index,
            textSize: widget.textSize,
            openBookCallback: widget.openBookCallback,
            viewportHeight: _viewportHeight,
          ),
      ],
    );
  }

  /// בדיקה אם יש מפרשים לאינדקס מסוים
  bool _hasCommentaries(TextBookLoaded state, int index) {
    // בדיקה אם יש קישורים רלוונטיים לאינדקס הזה
    final hasRelevantLinks = state.links.any((link) =>
        link.index1 == index + 1 &&
        (link.connectionType == "commentary" ||
            link.connectionType == "targum") &&
        state.activeCommentators.contains(utils.getTitleFromPath(link.path2)));

    return hasRelevantLinks;
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

class _CommentaryCard extends StatefulWidget {
  final int index;
  final double textSize;
  final Function(OpenedTab) openBookCallback;
  final double viewportHeight;

  const _CommentaryCard({
    super.key,
    required this.index,
    required this.textSize,
    required this.openBookCallback,
    required this.viewportHeight,
  });

  @override
  State<_CommentaryCard> createState() => _CommentaryCardState();
}

class _CommentaryCardState extends State<_CommentaryCard> {
  final GlobalKey<CommentaryListBaseState> _commentaryKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // חישוב גובה המפרשים לפי גובה הבלוק בפועל (לא כל המסך):
    // המפרשים יהיו 75% מגובה הבלוק
    // השאר (25%) יתחלק: 15% למעלה (טקסט), 10% למטה (טקסט)
    final maxHeight = widget.viewportHeight > 0
        ? widget.viewportHeight * 0.75
        : MediaQuery.of(context).size.height * 0.75;

    return LayoutBuilder(
      builder: (context, constraints) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            // שימוש באותו רוחב מקסימלי כמו הטקסט
            var textMaxWidth = settingsState.textMaxWidth;

            // אם הערך שלילי, זו רמה שצריך לחשב לפי גודל המסך
            if (textMaxWidth < 0) {
              final level = (-textMaxWidth).toInt();
              final widthPercent = 1.0 - (level * 0.05);
              textMaxWidth = constraints.maxWidth * widthPercent;
            }

            final commentaryContainer = Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxHeight,
                    minHeight: 50, // מינימום גובה למניעת בעיות layout
                  ),
                  child: CommentaryListBase(
                    key: _commentaryKey,
                    indexes: [widget.index],
                    fontSize: widget.textSize,
                    openBookCallback: widget.openBookCallback,
                    showSearch: false,
                    shrinkWrap: true,
                  ),
                ),
              ),
            );

            // אם יש רוחב מקסימלי, נמרכז את המפרשים באותו רוחב כמו הטקסט
            if (textMaxWidth > 0) {
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textMaxWidth),
                  child: commentaryContainer,
                ),
              );
            }
            return commentaryContainer;
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/models/link_types.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/models/books.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/utils/copy_utils.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';

/// תצוגת טקסט פשוטה - משמשת גם לטקסט המרכזי וגם למפרשים
class SimpleTextViewer extends StatefulWidget {
  final List<String> content;
  final double fontSize;
  final String? fontFamily;
  final Function(OpenedTab) openBookCallback;
  final ItemScrollController? scrollController;
  final ItemPositionsListener? positionsListener;
  final bool isMainText; // האם זה הטקסט המרכזי או מפרש
  final String? title; // כותרת (לכותרת עליונה)
  final String? bookTitle; // שם הספר (למפרשים - לפתיחה בטאב נפרד)
  final Set<int>? highlightedIndices; // אינדקסים להדגשה (למפרשים)
  final VoidCallback? onCommentatorChanged; // callback לרענון אחרי החלפת מפרש
  final bool useInternalScroll; // האם להשתמש בגלילה פנימית

  const SimpleTextViewer({
    super.key,
    required this.content,
    required this.fontSize,
    this.fontFamily,
    required this.openBookCallback,
    this.scrollController,
    this.positionsListener,
    this.isMainText = false,
    this.title,
    this.bookTitle,
    this.highlightedIndices,
    this.onCommentatorChanged,
    this.useInternalScroll = true, // ברירת מחדל - עם גלילה פנימית
  });

  @override
  State<SimpleTextViewer> createState() => _SimpleTextViewerState();
}

class _SimpleTextViewerState extends State<SimpleTextViewer> {
  late final ItemScrollController _scrollController;
  late final ItemPositionsListener _positionsListener;
  late final FocusNode _focusNode;
  String? _savedSelectedText;
  int? _savedSelectedIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ItemScrollController();
    _positionsListener =
        widget.positionsListener ?? ItemPositionsListener.create();
    _focusNode = FocusNode();

    // גלילה למיקום הנוכחי אחרי בניית הווידג'ט (רק לטקסט המרכזי)
    if (widget.isMainText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentPosition();
        // בקשת פוקוס לטקסט המרכזי כדי שהחיצים יעבדו
        if (mounted) {
          _focusNode.requestFocus();
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context.read<TextBookBloc>().state;
        if (state is TextBookLoaded) {
          context
              .read<PersonalNotesBloc>()
              .add(LoadPersonalNotes(state.book.title));
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// גלילה למיקום הנוכחי (selectedIndex או visibleIndices)
  void _scrollToCurrentPosition() {
    final bloc = context.read<TextBookBloc>();
    final state = bloc.state;
    if (state is TextBookLoaded && _scrollController.isAttached) {
      final targetIndex = state.selectedIndex ??
          (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : null);

      if (targetIndex != null && targetIndex < widget.content.length) {
        _scrollController.jumpTo(index: targetIndex);
      }
    }
  }

  /// טיפול באירועי מקלדת - חיצים לניווט
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!widget.isMainText) return false; // רק בטקסט המרכזי

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return false;

    // חיצים למעלה ולמטה
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final currentIndex = state.selectedIndex ?? 0;
      final nextIndex = (currentIndex + 1).clamp(0, widget.content.length - 1);
      if (nextIndex != currentIndex) {
        context.read<TextBookBloc>().add(UpdateSelectedIndex(nextIndex));
        if (_scrollController.isAttached) {
          _scrollController.scrollTo(
            index: nextIndex,
            duration: const Duration(milliseconds: 200),
            alignment: 0.5,
          );
        }
      }
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final currentIndex = state.selectedIndex ?? 0;
      final prevIndex = (currentIndex - 1).clamp(0, widget.content.length - 1);
      if (prevIndex != currentIndex) {
        context.read<TextBookBloc>().add(UpdateSelectedIndex(prevIndex));
        if (_scrollController.isAttached) {
          _scrollController.scrollTo(
            index: prevIndex,
            duration: const Duration(milliseconds: 200),
            alignment: 0.5,
          );
        }
      }
      return true;
    }

    // Page Down
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      final currentIndex = state.selectedIndex ?? 0;
      final nextIndex = (currentIndex + 10).clamp(0, widget.content.length - 1);
      context.read<TextBookBloc>().add(UpdateSelectedIndex(nextIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: nextIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
      }
      return true;
    }

    // Page Up
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      final currentIndex = state.selectedIndex ?? 0;
      final prevIndex = (currentIndex - 10).clamp(0, widget.content.length - 1);
      context.read<TextBookBloc>().add(UpdateSelectedIndex(prevIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: prevIndex,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
      }
      return true;
    }

    // Home - תחילת הספר
    if (event.logicalKey == LogicalKeyboardKey.home &&
        HardwareKeyboard.instance.isControlPressed) {
      context.read<TextBookBloc>().add(const UpdateSelectedIndex(0));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 300),
        );
      }
      return true;
    }

    // End - סוף הספר
    if (event.logicalKey == LogicalKeyboardKey.end &&
        HardwareKeyboard.instance.isControlPressed) {
      final lastIndex = widget.content.length - 1;
      context.read<TextBookBloc>().add(UpdateSelectedIndex(lastIndex));
      if (_scrollController.isAttached) {
        _scrollController.scrollTo(
          index: lastIndex,
          duration: const Duration(milliseconds: 300),
        );
      }
      return true;
    }

    return false;
  }

  /// תפריט הקשר - מעתיק מהתצוגה הרגילה
  ctx.ContextMenu _buildContextMenu(
      TextBookLoaded state, int index, BuildContext menuContext) {
    // בניית רשימת מפרשים אם זה מפרש (לא טקסט ראשי)
    List<ctx.MenuItem> commentatorMenuItems = [];
    if (!widget.isMainText && widget.bookTitle != null) {
      commentatorMenuItems = _buildCommentatorSwitchMenu(state);
    }

    return ctx.ContextMenu(
      entries: [
        ctx.MenuItem(
          label: const Text('חיפוש'),
          icon: const Icon(FluentIcons.search_24_regular),
          onSelected: (_) {
            // בצורת הדף אין חיפוש - אפשר להוסיף בעתיד
            UiSnack.show('חיפוש לא זמין בתצוגה זו');
          },
        ),
        // הוספת תפריט החלפת מפרש אם זה מפרש
        if (commentatorMenuItems.isNotEmpty) ...[
          const ctx.MenuDivider(),
          ...commentatorMenuItems,
        ],
        const ctx.MenuDivider(),
        // הערות אישיות
        ctx.MenuItem(
          label: const Text('הוסף הערה אישית '),
          icon: const Icon(FluentIcons.note_add_24_regular),
          onSelected: (_) => _createNoteForCurrentLine(index),
        ),
        // דיווח על טעות בספר
        ctx.MenuItem(
          label: const Text('דווח על טעות בספר'),
          icon: const Icon(FluentIcons.error_circle_24_regular),
          enabled: _savedSelectedText != null &&
              _savedSelectedText!.trim().isNotEmpty,
          onSelected: (_) => _openErrorReportDialog(_savedSelectedText!),
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
          enabled: index >= 0 && index < widget.content.length,
          onSelected: (_) => _copyParagraphByIndex(index),
        ),
        const ctx.MenuDivider(),
        // עריכת פסקה
        ctx.MenuItem(
          label: const Text('ערוך פסקה זו'),
          icon: const Icon(FluentIcons.edit_24_regular),
          onSelected: (_) => _editParagraph(index),
        ),
      ],
    );
  }

  /// יצירת הערה לשורה הנוכחית
  Future<void> _createNoteForCurrentLine(int index) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final selectedText = _savedSelectedText;
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? utils.removeVolwels(selectedText!.trim())
        : widget.content[index];

    // טען טיוטה אם קיימת
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: state.book.title,
      lineNumber: index + 1,
    );

    if (!mounted) return;

    // שלח event לפתיחת מצב יצירה בסיידבר
    context.read<PersonalNotesBloc>().add(StartCreatingPersonalNote(
          bookId: state.book.title,
          lineNumber: index + 1,
          referenceText: referenceText,
          selectedText: selectedText?.trim(),
          initialContent: draft?.content ?? '',
          initialFormat:
              draft?.contentFormat ?? PersonalNoteContentFormat.plain,
        ));
  }

  /// פתיחת דיאלוג דיווח על טעות בספר
  void _openErrorReportDialog(String selectedText) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    ErrorReportHelper.showErrorReportDialog(
      context: context,
      selectedText: selectedText,
      state: state,
      fontSize: widget.fontSize,
      bookTitle: widget.bookTitle ?? 'ספר לא ידוע',
      savedSelectedIndex: _savedSelectedIndex,
    );
  }

  /// עריכת פסקה
  void _editParagraph(int index) {
    if (index >= 0 && index < widget.content.length) {
      context.read<TextBookBloc>().add(OpenEditor(index: index));
    }
  }

  /// העתקת פסקה לפי אינדקס
  Future<void> _copyParagraphByIndex(int index) async {
    if (index < 0 || index >= widget.content.length) return;

    final text = widget.content[index];
    if (text.trim().isEmpty) return;

    final settingsState = context.read<SettingsBloc>().state;
    final textBookState = context.read<TextBookBloc>().state;

    String finalText = text;
    String finalHtmlText = text;

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

  /// עיצוב טקסט כ-HTML עם הגדרות הגופן הנוכחיות
  String _formatTextAsHtml(String text) {
    final settingsState = context.read<SettingsBloc>().state;
    final textWithBreaks = text.replaceAll('\n', '<br>');
    return '''
<div style="font-family: ${widget.fontFamily ?? settingsState.fontFamily}; font-size: ${widget.fontSize}px; text-align: justify; direction: rtl;">
$textWithBreaks
</div>
''';
  }

  /// העתקת טקסט מעוצב
  Future<void> _copyFormattedText() async {
    final plainText = _savedSelectedText;

    if (plainText == null || plainText.trim().isEmpty) {
      UiSnack.show('אנא בחר טקסט להעתקה');
      return;
    }

    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final settingsState = context.read<SettingsBloc>().state;
        final textBookState = context.read<TextBookBloc>().state;

        String htmlContentToUse = plainText;

        // אם יש לנו אינדקס נוכחי, ננסה למצוא את הטקסט המקורי
        if (_savedSelectedIndex != null &&
            _savedSelectedIndex! >= 0 &&
            _savedSelectedIndex! < widget.content.length) {
          final originalData = widget.content[_savedSelectedIndex!];
          final plainTextCleaned =
              plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
          final originalCleaned = originalData
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          if (originalCleaned.contains(plainTextCleaned) ||
              plainTextCleaned.contains(originalCleaned)) {
            htmlContentToUse = originalData;
          }
        }

        String finalPlainText = plainText;
        if (settingsState.copyWithHeaders != 'none' &&
            textBookState is TextBookLoaded) {
          final bookName = CopyUtils.extractBookName(textBookState.book);
          final currentIndex = _savedSelectedIndex ?? 0;
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

          htmlContentToUse = CopyUtils.formatTextWithHeaders(
            originalText: htmlContentToUse,
            copyWithHeaders: settingsState.copyWithHeaders,
            copyHeaderFormat: settingsState.copyHeaderFormat,
            bookName: bookName,
            currentPath: currentPath,
          );
        }

        await CopyUtils.copyStyledToClipboard(
          plainText: finalPlainText,
          htmlText: htmlContentToUse,
          fontFamily: widget.fontFamily ?? settingsState.fontFamily,
          fontSize: widget.fontSize,
        );
      }
    } catch (e) {
      if (mounted) {
        UiSnack.showError('שגיאה בהעתקה מעוצבת: $e',
            backgroundColor: Theme.of(context).colorScheme.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: widget.isMainText,
      onKeyEvent: (event) {
        if (_handleKeyEvent(event)) {
          // האירוע טופל
        }
      },
      child: Column(
        children: [
          // כותרת אופציונלית
          if (widget.title != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withAlpha(128),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  widget.title!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // תוכן
          Expanded(
            child: BlocBuilder<TextBookBloc, TextBookState>(
              builder: (context, state) {
                if (state is! TextBookLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }

                return BlocBuilder<PersonalNotesBloc, PersonalNotesState>(
                  builder: (context, notesState) {
                    final noteMap = <int, List<PersonalNote>>{};
                    if (notesState.bookId == state.book.title) {
                      for (final note in notesState.locatedNotes) {
                        final line = note.lineNumber;
                        if (line == null) continue;
                        noteMap.putIfAbsent(line, () => []).add(note);
                      }
                    }

                    return SelectionArea(
                      onSelectionChanged: (selection) {
                        // שמירת הטקסט הנבחר
                        if (selection != null) {
                          setState(() {
                            _savedSelectedText = selection.plainText;
                          });
                        }
                      },
                      child: widget.useInternalScroll
                          ? ScrollablePositionedList.builder(
                              itemScrollController: _scrollController,
                              itemPositionsListener: _positionsListener,
                              itemCount: widget.content.length,
                              padding: const EdgeInsets.all(4),
                              itemBuilder: (context, index) =>
                                  _buildLine(index, state, context, noteMap),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: widget.content.length,
                              padding: const EdgeInsets.all(4),
                              itemBuilder: (context, index) =>
                                  _buildLine(index, state, context, noteMap),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(
    int index,
    TextBookLoaded state,
    BuildContext context,
    Map<int, List<PersonalNote>> noteMap,
  ) {
    final isSelected = widget.isMainText && state.selectedIndex == index;
    final isHighlighted = widget.isMainText && state.highlightedLine == index;

    // בדיקה חדשה - האם השורה מודגשת כפרשן קשור (מקומי)
    final isCommentaryHighlighted = !widget.isMainText &&
        (widget.highlightedIndices?.contains(index) ?? false);

    final theme = Theme.of(context);
    final backgroundColor = () {
      if (isHighlighted) {
        return theme.colorScheme.secondaryContainer
            .withAlpha((0.4 * 255).round());
      }
      if (isCommentaryHighlighted || isSelected) {
        // צבע הדגשה למפרש קשור - כמו השורה הנבחרת
        return theme.colorScheme.primary.withAlpha((0.08 * 255).round());
      }
      return null;
    }();

    final notesForLine = noteMap[index + 1] ?? const <PersonalNote>[];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.isMainText
          ? () {
              // איפוס הטקסט השמור
              setState(() {
                _savedSelectedText = null;
                _savedSelectedIndex = null;
              });
              // עדכון selectedIndex רק בטקסט המרכזי
              if (isSelected) {
                context
                    .read<TextBookBloc>()
                    .add(const UpdateSelectedIndex(null));
              } else {
                context.read<TextBookBloc>().add(UpdateSelectedIndex(index));
              }
            }
          : null,
      onDoubleTap: !widget.isMainText && widget.bookTitle != null
          ? () {
              // לחיצה כפולה במפרש - פתיחה בטאב נפרד
              widget.openBookCallback(TextBookTab(
                book: TextBook(title: widget.bookTitle!),
                index: index,
                openLeftPane:
                    (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                        (Settings.getValue<bool>('key-default-sidebar-open') ??
                            false),
              ));
            }
          : null,
      onSecondaryTapDown: (details) {
        // שמירת האינדקס לשימוש בתפריט ההקשר
        setState(() {
          _savedSelectedIndex = index;
        });
      },
      child: ctx.ContextMenuRegion(
        contextMenu: _buildContextMenu(state, index, context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: backgroundColor != null
              ? BoxDecoration(color: backgroundColor)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              final data = widget.content[index];

              // הדגשת טקסט חיפוש רק בטקסט המרכזי
              final searchText = widget.isMainText ? state.searchText : '';

              final textWidget = SmartTextWidget(
                text: data,
                widgetKey: ValueKey('html_simple_text_$index'),
                settings: RenderSettings(
                  removeNikud: state.removeNikud,
                  removeTeamim: !settingsState.showTeamim,
                  replaceHolyNames: settingsState.replaceHolyNames,
                  searchText: searchText,
                  fontSize: widget.fontSize,
                  fontFamily: widget.fontFamily ?? settingsState.fontFamily,
                  lineHeight: settingsState.lineHeight,
                ),
                onOpenBook: widget.openBookCallback,
              );

              if (!widget.isMainText || notesForLine.isEmpty) {
                return textWidget;
              }

              final note = notesForLine.first;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: note.contentPlain,
                    child: GestureDetector(
                      onTap: () {
                        context
                            .read<TextBookBloc>()
                            .add(UpdateSelectedIndex(index));
                        context.read<TextBookBloc>().add(HighlightLine(index));
                        context
                            .read<TextBookBloc>()
                            .add(const ToggleLeftPane(true));
                      },
                      onLongPress: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('הערה לשורה זו'),
                            content: PersonalNoteContentView(note: note),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('סגור'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, right: 2),
                        child: Icon(
                          FluentIcons.note_24_filled,
                          size: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: textWidget),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// בניית תפריט החלפת מפרש
  List<ctx.MenuItem> _buildCommentatorSwitchMenu(TextBookLoaded state) {
    // קבלת רשימת המפרשים הזמינים
    final availableCommentators = state.links
        .where((link) => LinkTypes.isCommentaryOrTargum(link.connectionType))
        .map((link) => utils.getTitleFromPath(link.path2))
        .toSet()
        .toList();

    if (availableCommentators.isEmpty) {
      return [];
    }

    // קיבוץ המפרשים לפי קבוצות
    final groups = state.commentatorGroups;
    final tanachGroup = CommentatorGroup.groupByTitle(groups, 'תורה שבכתב');
    final chazalGroup = CommentatorGroup.groupByTitle(groups, 'תורה שבעל פה');
    final rishonimGroup = CommentatorGroup.groupByTitle(groups, 'ראשונים');
    final acharonimGroup = CommentatorGroup.groupByTitle(groups, 'אחרונים');
    final modernGroup = CommentatorGroup.groupByTitle(groups, 'מודרני');

    final allGrouped = [
      ...tanachGroup.commentators,
      ...chazalGroup.commentators,
      ...rishonimGroup.commentators,
      ...acharonimGroup.commentators,
      ...modernGroup.commentators,
    ];
    final ungrouped =
        availableCommentators.where((c) => !allGrouped.contains(c)).toList();

    // בניית תפריט משנה
    final submenuItems = <dynamic>[];

    // הוספת קבוצות
    if (tanachGroup.commentators.isNotEmpty) {
      submenuItems
          .addAll(_buildCommentatorGroupItems(tanachGroup.commentators, state));
    }
    if (chazalGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems
          .addAll(_buildCommentatorGroupItems(chazalGroup.commentators, state));
    }
    if (rishonimGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems.addAll(
          _buildCommentatorGroupItems(rishonimGroup.commentators, state));
    }
    if (acharonimGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems.addAll(
          _buildCommentatorGroupItems(acharonimGroup.commentators, state));
    }
    if (modernGroup.commentators.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems
          .addAll(_buildCommentatorGroupItems(modernGroup.commentators, state));
    }
    if (ungrouped.isNotEmpty) {
      if (submenuItems.isNotEmpty) submenuItems.add(const ctx.MenuDivider());
      submenuItems.addAll(_buildCommentatorGroupItems(ungrouped, state));
    }

    return [
      ctx.MenuItem.submenu(
        label: const Text('החלף מפרש'),
        icon: const Icon(FluentIcons.arrow_swap_24_regular),
        items: submenuItems.cast<ctx.ContextMenuEntry>(),
      ),
    ];
  }

  /// בניית פריטי תפריט לקבוצת מפרשים
  List<ctx.MenuItem> _buildCommentatorGroupItems(
      List<String> commentators, TextBookLoaded state) {
    return commentators.map((commentator) {
      final isSelected = commentator == widget.bookTitle;
      return ctx.MenuItem<void>(
        label: Text(commentator),
        icon: isSelected ? const Icon(FluentIcons.checkmark_24_regular) : null,
        onSelected: (_) => _switchCommentator(commentator, state),
      );
    }).toList();
  }

  /// החלפת מפרש
  void _switchCommentator(String newCommentator, TextBookLoaded state) {
    if (newCommentator == widget.bookTitle) {
      return; // כבר מוצג מפרש זה
    }

    // צריך למצוא באיזה טור המפרש הנוכחי מוצג ולהחליף אותו
    final config = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );

    if (config == null) return;

    // מציאת הטור שבו המפרש הנוכחי מוצג
    String? columnToUpdate;
    for (final entry in config.entries) {
      if (entry.value == null) continue;

      // בדיקה אם המפרש הנוכחי תואם לערך בהגדרה
      final configValue = entry.value!;
      final currentTitle = widget.bookTitle!;

      if (configValue == currentTitle ||
          currentTitle.startsWith(configValue) ||
          currentTitle.contains(configValue) ||
          configValue.startsWith(currentTitle) ||
          configValue.contains(currentTitle)) {
        columnToUpdate = entry.key;
        break;
      }
    }

    if (columnToUpdate == null) {
      debugPrint(
          '⚠️ PageShape: Could not find column for commentator "${widget.bookTitle}"');
      return;
    }

    // עדכון ההגדרה
    final updatedConfig = Map<String, String?>.from(config);
    updatedConfig[columnToUpdate] = newCommentator;

    // בדיקה אם יש הגדרה ספציפית לספר (לא רק הדגל, אלא הגדרה ממשית)
    final hasActualBookConfig =
        PageShapeSettingsManager.loadConfiguration(state.book.title) != null;

    // אם יש הגדרה ספציפית לספר - שומרים לספר
    // אחרת - שומרים לקטגוריה (אם יש)
    final categoryToSave = !hasActualBookConfig &&
            state.book.heCategories != null &&
            state.book.heCategories!.isNotEmpty
        ? state.book.heCategories
        : null;

    PageShapeSettingsManager.saveConfiguration(
      state.book.title,
      updatedConfig,
      saveToCategory: categoryToSave,
    );

    // קריאה ל-callback לרענון המסך
    widget.onCommentatorChanged?.call();
  }
}

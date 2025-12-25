import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/html_link_handler.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/models/books.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/utils/copy_utils.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

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
  });

  @override
  State<SimpleTextViewer> createState() => _SimpleTextViewerState();
}

class _SimpleTextViewerState extends State<SimpleTextViewer> {
  late final ItemScrollController _scrollController;
  late final ItemPositionsListener _positionsListener;
  String? _savedSelectedText;
  int? _savedSelectedIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ItemScrollController();
    _positionsListener =
        widget.positionsListener ?? ItemPositionsListener.create();

    // גלילה למיקום הנוכחי אחרי בניית הווידג'ט (רק לטקסט המרכזי)
    if (widget.isMainText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentPosition();
      });
    }
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

  /// תפריט הקשר - מעתיק מהתצוגה הרגילה
  ctx.ContextMenu _buildContextMenu(
      TextBookLoaded state, int index, BuildContext menuContext) {
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
        const ctx.MenuDivider(),
        // הערות אישיות
        ctx.MenuItem(
          label: const Text('הוסף הערה אישית '),
          icon: const Icon(FluentIcons.note_add_24_regular),
          onSelected: (_) => _createNoteForCurrentLine(index),
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
  void _createNoteForCurrentLine(int index) {
    final controller = TextEditingController();
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final selectedText = _savedSelectedText;
    final referenceText = selectedText?.trim().isNotEmpty == true
        ? utils.removeVolwels(selectedText!.trim())
        : widget.content[index];

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
        final lineNumber = index + 1;
        context.read<PersonalNotesBloc>().add(AddPersonalNote(
              bookId: state.book.title,
              lineNumber: lineNumber,
              content: trimmed,
              selectedText: selectedText?.trim(),
            ));
        UiSnack.show('ההערה נשמרה בהצלחה');
      } catch (e) {
        UiSnack.showError('שמירת ההערה נכשלה: $e');
      }
    });
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
    return Column(
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

              return SelectionArea(
                onSelectionChanged: (selection) {
                  // שמירת הטקסט הנבחר
                  if (selection != null) {
                    setState(() {
                      _savedSelectedText = selection.plainText;
                    });
                  }
                },
                child: ScrollablePositionedList.builder(
                  itemScrollController: _scrollController,
                  itemPositionsListener: _positionsListener,
                  itemCount: widget.content.length,
                  padding: const EdgeInsets.all(4),
                  itemBuilder: (context, index) =>
                      _buildLine(index, state, context),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLine(int index, TextBookLoaded state, BuildContext context) {
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
              String data = widget.content[index];

              // החלת מניפולציות טקסט
              if (!settingsState.showTeamim) {
                data = utils.removeTeamim(data);
              }
              if (settingsState.replaceHolyNames) {
                data = utils.replaceHolyNames(data);
              }
              if (state.removeNikud) {
                data = utils.removeVolwels(data);
              }

              // הדגשת טקסט חיפוש (רק בטקסט המרכזי)
              String processedData = data;
              if (widget.isMainText && state.searchText.isNotEmpty) {
                processedData = state.removeNikud
                    ? utils.highLight(
                        utils.removeVolwels('$data\n'), state.searchText)
                    : utils.highLight('$data\n', state.searchText);
              }

              processedData = utils.formatTextWithParentheses(processedData);

              return HtmlWidget(
                '''
              <div style="text-align: justify; direction: rtl;">
                $processedData
              </div>
              ''',
                key: ValueKey('html_simple_text_$index'),
                textStyle: TextStyle(
                  fontSize: widget.fontSize,
                  fontFamily: widget.fontFamily ?? settingsState.fontFamily,
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
            },
          ),
        ),
      ),
    );
  }
}

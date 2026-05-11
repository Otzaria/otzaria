import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';

/// חלון עצמאי להצגת מפרשים לשורה ספציפית בספר.
///
/// פותח כ-dialog מלא-מסך מתוך [TabbedCommentaryPanel].
/// משתף את ה-[TextBookBloc] הקיים דרך [BlocProvider.value].
class StandaloneCommentatorsDialog extends StatefulWidget {
  final int initialLineIndex; // 0-based
  final int totalLines;
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final String bookTitle;

  const StandaloneCommentatorsDialog({
    super.key,
    required this.initialLineIndex,
    required this.totalLines,
    required this.openBookCallback,
    required this.fontSize,
    required this.bookTitle,
  });

  @override
  State<StandaloneCommentatorsDialog> createState() =>
      _StandaloneCommentatorsDialogState();
}

class _StandaloneCommentatorsDialogState
    extends State<StandaloneCommentatorsDialog> {
  late final TextEditingController _lineController;
  late int _currentIndex; // 0-based

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialLineIndex;
    _lineController =
        TextEditingController(text: '${widget.initialLineIndex + 1}');
  }

  @override
  void dispose() {
    _lineController.dispose();
    super.dispose();
  }

  void _applyLineNumber() {
    final lineNum = int.tryParse(_lineController.text.trim());
    if (lineNum == null || lineNum < 1 || lineNum > widget.totalLines) return;
    setState(() {
      _currentIndex = lineNum - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog.fullscreen(
        child: Scaffold(
          body: Column(
            children: [
              // ─── Header ───────────────────────────────────────────────
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    // כפתור סגירה
                    IconButton(
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                      tooltip: 'סגור',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    // כותרת
                    Expanded(
                      child: Text(
                        'מפרשים — ${widget.bookTitle}',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // שדה קלט מספר שורה
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _lineController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'שורה',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          hintText: '1–${widget.totalLines}',
                        ),
                        onSubmitted: (_) => _applyLineNumber(),
                        textInputAction: TextInputAction.go,
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _applyLineNumber,
                      child: const Text('הצג'),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              // ─── תוכן מפרשים ──────────────────────────────────────────
              Expanded(
                child: CommentaryListBase(
                  key: ValueKey(_currentIndex),
                  openBookCallback: widget.openBookCallback,
                  fontSize: widget.fontSize,
                  indexes: [_currentIndex],
                  showSearch: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// פותח את [StandaloneCommentatorsDialog] מתוך כל [BuildContext]
/// שמכיל [TextBookBloc].
void openStandaloneCommentatorsDialog({
  required BuildContext context,
  required Function(OpenedTab) openBookCallback,
  required double fontSize,
}) {
  final bloc = context.read<TextBookBloc>();
  final state = bloc.state;
  if (state is! TextBookLoaded) return;

  final initialIndex = state.selectedIndex ??
      (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) => BlocProvider.value(
      value: bloc,
      child: StandaloneCommentatorsDialog(
        initialLineIndex: initialIndex,
        totalLines: state.content.length,
        openBookCallback: openBookCallback,
        fontSize: fontSize,
        bookTitle: state.book.title,
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// פאנל תצוגה מקדימה של ספר בספרייה
/// מציג את תוכן הספר בלי כרטיסיות, בדומה לחלון העיון
class BookPreviewPanel extends StatefulWidget {
  final Book? book;
  final VoidCallback? onOpenInReader;
  final VoidCallback? onClose;

  const BookPreviewPanel({
    super.key,
    this.book,
    this.onOpenInReader,
    this.onClose,
  });

  @override
  State<BookPreviewPanel> createState() => _BookPreviewPanelState();
}

class _BookPreviewPanelState extends State<BookPreviewPanel> {
  TextBookTab? _currentTab;

  @override
  void didUpdateWidget(BookPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // אם הספר השתנה, נצור tab חדש
    if (widget.book != oldWidget.book && widget.book != null) {
      _disposeCurrentTab();
      _createNewTab();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.book != null) {
      _createNewTab();
    }
  }

  @override
  void dispose() {
    _disposeCurrentTab();
    super.dispose();
  }

  void _disposeCurrentTab() {
    _currentTab?.dispose();
    _currentTab = null;
  }

  void _createNewTab() {
    if (widget.book == null || widget.book is! TextBook) return;

    setState(() {
      _currentTab = TextBookTab(
        book: widget.book as TextBook,
        index: 0,
        searchText: '',
        openLeftPane: false,
        splitedView: Settings.getValue<bool>('key-splited-view') ?? false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.book_24_regular,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'בחר ספר לתצוגה מקדימה',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    // אם זה ספר PDF או חיצוני
    if (widget.book is! TextBook) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.book is PdfBook
                  ? FluentIcons.document_pdf_24_regular
                  : FluentIcons.link_24_regular,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              widget.book!.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.book is PdfBook
                  ? 'ספר PDF - לחץ פעמיים לפתיחה'
                  : 'ספר חיצוני - לחץ פעמיים לפתיחה',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: widget.onOpenInReader,
              icon: const Icon(FluentIcons.open_24_regular),
              label: const Text('פתח בעיון'),
            ),
          ],
        ),
      );
    }

    // תצוגת ספר טקסט
    if (_currentTab == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // תוכן הספר (מלא את כל השטח)
        BlocProvider.value(
          value: _currentTab!.bloc,
          child: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              return BlocBuilder(
                bloc: _currentTab!.bloc,
                builder: (context, state) {
                  if (state is TextBookInitial) {
                    _currentTab!.bloc.add(
                      LoadContent(
                        fontSize: settingsState.fontSize,
                        showSplitView: false,
                        removeNikud: settingsState.defaultRemoveNikud,
                      ),
                    );
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is TextBookLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is TextBookError) {
                    return Center(
                      child: Text('שגיאה: ${state.message}'),
                    );
                  }

                  if (state is TextBookLoaded) {
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: settingsState.paddingSize,
                      ),
                      child: CombinedView(
                        data: state.content,
                        textSize: state.fontSize,
                        openBookCallback: (tab) {},
                        openLeftPaneTab: (index) {},
                        showCommentaryAsExpansionTiles: false,
                        tab: _currentTab!,
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
        // כפתורים צפים בפינה השמאלית העליונה (משטח אחד)
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // כפתור פתיחה בעיון
                IconButton(
                  icon: const Icon(FluentIcons.open_24_regular, size: 20),
                  tooltip: 'פתח בעיון (או לחץ פעמיים על הספר)',
                  onPressed: widget.onOpenInReader,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                // קו מפריד
                if (widget.onClose != null)
                  Container(
                    width: 1,
                    height: 24,
                    color: Theme.of(context).dividerColor,
                  ),
                // כפתור סגירה
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
                    tooltip: 'הסתר תצוגה מקדימה',
                    onPressed: widget.onClose,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

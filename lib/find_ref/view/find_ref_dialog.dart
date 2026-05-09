import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class FindRefDialog extends StatefulWidget {
  const FindRefDialog({super.key});

  @override
  State<FindRefDialog> createState() => _FindRefDialogState();
}

class _FindRefDialogState extends State<FindRefDialog> {
  int _selectedIndex = 0;
  final Map<int, GlobalKey> _itemKeys = {};
  FocusRestorer? _focusRestorer;

  @override
  void initState() {
    super.initState();

    // בחירת הטקסט הקיים כאשר חוזרים למסך
    // מבוצע מיד ולא ב-postFrameCallback כדי למנוע אובדן פוקוס באנדרואיד
    final controller = FocusRepository().findRefSearchController;
    if (controller.text.isNotEmpty) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }

    // רישום כ-active restorer כדי שהדיאלוג יקבל שחזור פוקוס לאחר אירועי חלון
    _focusRestorer = FocusRepository().registerActiveRestorer(
      restore: () {
        if (mounted) FocusRepository().findRefSearchFocusNode.requestFocus();
      },
      canRestore: () =>
          mounted &&
          FocusRepository().findRefSearchFocusNode.canRequestFocus &&
          (ModalRoute.of(context)?.isCurrent ?? false),
    );
  }

  @override
  void dispose() {
    final restorer = _focusRestorer;
    if (restorer != null) FocusRepository().unregisterActiveRestorer(restorer);
    super.dispose();
  }

  GlobalKey _getKeyForIndex(int index) {
    if (!_itemKeys.containsKey(index)) {
      _itemKeys[index] = GlobalKey();
    }
    return _itemKeys[index]!;
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _getKeyForIndex(_selectedIndex);
      final context = key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: 0.5, // מרכז המסך
        );
      }
    });
  }

  Future<void> _openRef(DbReferenceResult ref) async {
    Book? book;

    if (ref.isPdf && ref.filePath.isNotEmpty) {
      // Use filePath directly — library search may return a same-titled text book
      book = PdfBook(title: ref.title, path: ref.filePath);
    } else {
      try {
        final library = await DataRepository.instance.library;
        book = _findBookInLibrary(library, ref.title);
      } catch (e) {
        debugPrint('Error searching library: $e');
      }
      book ??= TextBook(title: ref.title);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    openBook(context, book, ref.segment.toInt(), '',
        ignoreHistory: ref.isPdf);
  }

  Book? _findBookInLibrary(Category category, String title) {
    for (final b in category.books) {
      if (b.title == title) return b;
    }
    for (final subCat in category.subCategories) {
      final found = _findBookInLibrary(subCat, title);
      if (found != null) return found;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final focusRepository = context.read<FocusRepository>();

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'סגור',
          ),
          const Expanded(
            child: Text(
              'איתור מקורות',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48), // מאזן את האייקון בצד השני
        ],
      ),
      content: SizedBox(
        key: tourFindRefDialogTargetKey,
        width: 500,
        height: 600,
        child: Column(
          children: [
            BlocBuilder<FindRefBloc, FindRefState>(
              builder: (context, state) {
                final refs = state is FindRefSuccess ? state.refs : [];
                return Focus(
                  onKeyEvent: (node, event) {
                    // טיפול גם ב-KeyDownEvent וגם ב-KeyRepeatEvent (לחיצה רצופה)
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }

                    // טיפול בחיצים רק אם יש תוצאות
                    if (refs.isNotEmpty) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        setState(() {
                          _selectedIndex =
                              (_selectedIndex + 1).clamp(0, refs.length - 1);
                        });
                        _scrollToSelected();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey ==
                          LogicalKeyboardKey.arrowUp) {
                        setState(() {
                          _selectedIndex =
                              (_selectedIndex - 1).clamp(0, refs.length - 1);
                        });
                        _scrollToSelected();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: RtlTextField(
                    focusNode: focusRepository.findRefSearchFocusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText:
                          'הקלד מקור מדוייק, לדוגמה: בראשית פרק א או שוע אוח יב   ',
                      suffixIcon: IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () {
                          focusRepository.findRefSearchController.clear();
                          BlocProvider.of<FindRefBloc>(context)
                              .add(ClearSearchRequested());
                          setState(() {
                            _selectedIndex = 0;
                          });
                        },
                      ),
                    ),
                    controller: focusRepository.findRefSearchController,
                    onChanged: (ref) {
                      BlocProvider.of<FindRefBloc>(context)
                          .add(SearchRefRequested(ref));
                      setState(() {
                        _selectedIndex = 0;
                      });
                    },
                    onSubmitted: (value) {
                      // פתיחת המקור הנבחר בלחיצה על אנטר
                      if (refs.isNotEmpty) {
                        _openRef(refs[_selectedIndex]);
                      }
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<FindRefBloc, FindRefState>(
                builder: (context, state) {
                  if (state is FindRefLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is FindRefError) {
                    return Text('Error: ${state.message}');
                  } else if (state is FindRefSuccess && state.refs.isEmpty) {
                    if (focusRepository.findRefSearchController.text.length >=
                        3) {
                      return const Center(
                        child: Text(
                          'אין תוצאות',
                          style: TextStyle(fontSize: 16),
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  } else if (state is FindRefSuccess) {
                    return ListView.builder(
                      itemCount: state.refs.length,
                      itemBuilder: (context, index) {
                        final isSelected = index == _selectedIndex;
                        return Container(
                          key: _getKeyForIndex(index),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: ListTile(
                              leading: state.refs[index].isPdf
                                  ? const Icon(
                                      FluentIcons.document_pdf_24_regular)
                                  : null,
                              title: Text(
                                state.refs[index].reference,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              onTap: () {
                                _openRef(state.refs[index]);
                              }),
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('סגור'),
        ),
      ],
    );
  }
}

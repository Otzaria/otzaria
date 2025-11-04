import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/find_ref/find_ref_bloc.dart';
import 'package:otzaria/find_ref/find_ref_event.dart';
import 'package:otzaria/find_ref/find_ref_state.dart';
import 'package:otzaria/focus/focus_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/open_book.dart';

class FindRefDialog extends StatefulWidget {
  const FindRefDialog({super.key});

  @override
  State<FindRefDialog> createState() => _FindRefDialogState();
}

class _FindRefDialogState extends State<FindRefDialog> {
  bool showIndexWarning = false;

  @override
  void initState() {
    super.initState();
    if (context.read<IndexingBloc>().state is IndexingInProgress) {
      showIndexWarning = true;
    }
  }

  Widget _buildIndexingWarning() {
    if (showIndexWarning) {
      return Container(
        padding: const EdgeInsets.all(8.0),
        margin: const EdgeInsets.only(bottom: 8.0),
        decoration: BoxDecoration(
          color: Colors.yellow.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(FluentIcons.warning_24_regular, color: Colors.orange[700]),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'אינדקס המקורות בתהליך בנייה. תוצאות החיפוש עלולות להיות חלקיות.',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.black87),
              ),
            ),
            IconButton(
                onPressed: () => setState(() => showIndexWarning = false),
                icon: const Icon(FluentIcons.dismiss_24_regular))
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final focusRepository = context.read<FocusRepository>();

    return AlertDialog(
      title: const Text(
        'איתור מקורות',
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            _buildIndexingWarning(),
            TextField(
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
                  },
                ),
              ),
              controller: focusRepository.findRefSearchController,
              onChanged: (ref) {
                BlocProvider.of<FindRefBloc>(context)
                    .add(SearchRefRequested(ref));
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
                        return ListTile(
                            leading: state.refs[index].isPdf
                                ? const Icon(FluentIcons.document_pdf_24_regular)
                                : null,
                            title: Text(state.refs[index].reference),
                            onTap: () {
                              final ref = state.refs[index];
                              final book = ref.isPdf
                                  ? PdfBook(
                                      title: ref.title, path: ref.filePath)
                                  : TextBook(title: ref.title);
                              // סגירת הדיאלוג לפני פתיחת הספר
                              Navigator.of(context).pop();
                              openBook(context, book, ref.segment.toInt(), '');
                            });
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

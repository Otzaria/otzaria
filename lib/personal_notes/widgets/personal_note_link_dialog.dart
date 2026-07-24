import 'package:flutter/material.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class PersonalNoteLinkTarget {
  final String label;
  final String url;

  const PersonalNoteLinkTarget({required this.label, required this.url});
}

class PersonalNoteLinkDialog extends StatefulWidget {
  final String? bookId;
  final List<PersonalNote> notes;

  const PersonalNoteLinkDialog({
    super.key,
    required this.notes,
    this.bookId,
  });

  @override
  State<PersonalNoteLinkDialog> createState() => _PersonalNoteLinkDialogState();
}

class _PersonalNoteLinkDialogState extends State<PersonalNoteLinkDialog> {
  final TextEditingController _lineController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  int _selectedTab = 0;
  PersonalNote? _selectedNote;
  String? _urlError;

  @override
  void dispose() {
    _lineController.dispose();
    _labelController.dispose();
    _searchController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// קישור מודבק תקין: כתובת אינטרנט, או קישור עמוק של האפליקציה שניתן לפענוח.
  static bool _isValidPastedLink(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') return true;
    return ExternalUriRouter.parseUri(uri) != null;
  }

  void _submit() {
    if (_selectedTab == 0) {
      final lineNumber = int.tryParse(_lineController.text.trim());
      if (lineNumber == null || lineNumber <= 0) return;
      final bookId = widget.bookId ?? '';
      final label = _labelController.text.trim().isEmpty
          ? 'שורה $lineNumber'
          : _labelController.text.trim();
      final url = 'otzaria://book?bookId=$bookId&line=$lineNumber';
      Navigator.of(context).pop(
        PersonalNoteLinkTarget(label: label, url: url),
      );
      return;
    }

    if (_selectedTab == 2) {
      final url = _urlController.text.trim();
      final uri = Uri.tryParse(url);
      if (url.isEmpty || uri == null || !_isValidPastedLink(uri)) {
        setState(() => _urlError = 'קישור לא תקין או לא נתמך');
        return;
      }
      final label = _labelController.text.trim().isEmpty
          ? url
          : _labelController.text.trim();
      Navigator.of(context).pop(PersonalNoteLinkTarget(label: label, url: url));
      return;
    }

    final note = _selectedNote;
    if (note == null) return;
    final label = _labelController.text.trim().isEmpty
        ? (note.displayTitle?.trim().isNotEmpty == true
              ? note.displayTitle!.trim()
              : 'הערה')
        : _labelController.text.trim();
    final url = 'otzaria://note?id=${note.id}';
    Navigator.of(context).pop(PersonalNoteLinkTarget(label: label, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = widget.notes.where((note) {
      final query = _searchController.text.trim().toLowerCase();
      if (query.isEmpty) return true;
      return note.contentPlain.toLowerCase().contains(query) ||
          (note.displayTitle?.toLowerCase().contains(query) ?? false) ||
          note.id.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      title: const Text('הוסף קישור'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToggleButtons(
              isSelected: [
                _selectedTab == 0,
                _selectedTab == 1,
                _selectedTab == 2,
              ],
              onPressed: (index) {
                setState(() {
                  _selectedTab = index;
                  _labelController.clear();
                  _urlError = null;
                });
              },
              borderRadius: AppTokens.borderRadiusAll,
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('קישור לספר'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('קישור להערה'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('הדבקת קישור'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_selectedTab == 2)
              Column(
                children: [
                  RtlTextField(
                    controller: _urlController,
                    autofocus: true,
                    textAlign: TextAlign.left,
                    decoration: InputDecoration(
                      labelText: 'כתובת הקישור',
                      hintText: 'otzaria://open/book/2156 או https://...',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _urlError,
                    ),
                    onChanged: (_) {
                      if (_urlError != null) setState(() => _urlError = null);
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  RtlTextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'טקסט לקישור (אופציונלי)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              )
            else if (_selectedTab == 0)
              Column(
                children: [
                  RtlTextField(
                    controller: _lineController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'מספר שורה',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  RtlTextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'טקסט לקישור (אופציונלי)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  RtlTextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'חיפוש הערה',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount: filteredNotes.length,
                      itemBuilder: (context, index) {
                        final note = filteredNotes[index];
                        final selected = note.id == _selectedNote?.id;
                        return ListTile(
                          title: Text(
                            note.displayTitle?.trim().isNotEmpty == true
                                ? note.displayTitle!
                                : note.contentPlain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            note.contentPlain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: selected,
                          onTap: () => setState(() => _selectedNote = note),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  RtlTextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'טקסט לקישור (אופציונלי)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        ActionButton.neutral(
          text: 'ביטול',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
          text: 'הוסף',
          onPressed: _submit,
        ),
      ],
    );
  }
}

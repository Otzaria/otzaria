import 'package:flutter/material.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

enum NotesExportMode {
  all,
  byBook,
  byDateRange,
  manual,
}

class NotesExportSelection {
  final List<PersonalNote> notes;
  final String description;

  const NotesExportSelection({required this.notes, required this.description});
}

class PersonalNotesExportDialog extends StatefulWidget {
  final List<PersonalNote> allNotes;

  const PersonalNotesExportDialog({
    super.key,
    required this.allNotes,
  });

  @override
  State<PersonalNotesExportDialog> createState() =>
      _PersonalNotesExportDialogState();
}

class _PersonalNotesExportDialogState extends State<PersonalNotesExportDialog> {
  NotesExportMode _mode = NotesExportMode.all;
  String? _selectedBookId;
  DateTimeRange? _dateRange;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _manualSelection = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submit() {
    final selection = _buildSelection();
    Navigator.of(context).pop(selection);
  }

  NotesExportSelection _buildSelection() {
    final notes = widget.allNotes;
    List<PersonalNote> result = notes;
    String description = 'כל ההערות';

    if (_mode == NotesExportMode.byBook && _selectedBookId != null) {
      result = notes.where((note) => note.bookId == _selectedBookId).toList();
      description = 'הערות לספר $_selectedBookId';
    } else if (_mode == NotesExportMode.byDateRange && _dateRange != null) {
      result = notes
          .where((note) =>
              note.updatedAt.isAfter(_dateRange!.start) &&
              note.updatedAt.isBefore(_dateRange!.end))
          .toList();
      description =
          'הערות בתאריכים ${_dateRange!.start.toIso8601String()} - ${_dateRange!.end.toIso8601String()}';
    } else if (_mode == NotesExportMode.manual) {
      result =
          notes.where((note) => _manualSelection[note.id] == true).toList();
      description = 'בחירה ידנית (${result.length})';
    }

    return NotesExportSelection(notes: result, description: description);
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.allNotes.map((note) => note.bookId).toSet().toList()
      ..sort();

    final filteredNotes = widget.allNotes.where((note) {
      final query = _searchController.text.trim().toLowerCase();
      if (query.isEmpty) return true;
      return note.contentPlain.toLowerCase().contains(query) ||
          note.bookId.toLowerCase().contains(query) ||
          (note.displayTitle?.toLowerCase().contains(query) ?? false);
    }).toList();

    return AlertDialog(
      title: const Text('ייצוא הערות'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NotesExportMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(_labelForMode(mode)),
                  selected: _mode == mode,
                  onSelected: (_) => setState(() => _mode = mode),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (_mode == NotesExportMode.byBook)
              DropdownButtonFormField<String>(
                initialValue: _selectedBookId,
                items: books
                    .map((bookId) => DropdownMenuItem(
                          value: bookId,
                          child: Text(bookId),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _selectedBookId = value),
                decoration: const InputDecoration(
                  labelText: 'בחר ספר',
                  border: OutlineInputBorder(),
                ),
              ),
            if (_mode == NotesExportMode.byDateRange)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_dateRange == null
                    ? 'בחר טווח תאריכים'
                    : '${_dateRange!.start.toString().split(' ').first} - ${_dateRange!.end.toString().split(' ').first}'),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _dateRange = picked);
                  }
                },
              ),
            if (_mode == NotesExportMode.manual) ...[
              RtlTextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'חיפוש הערות',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: filteredNotes.length,
                  itemBuilder: (context, index) {
                    final note = filteredNotes[index];
                    final selected = _manualSelection[note.id] ?? false;
                    return CheckboxListTile(
                      value: selected,
                      title: Text(note.displayTitle?.isNotEmpty == true
                          ? note.displayTitle!
                          : note.bookId),
                      subtitle: Text(
                        note.contentPlain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (value) {
                        setState(
                            () => _manualSelection[note.id] = value ?? false);
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ייצא'),
        ),
      ],
    );
  }

  String _labelForMode(NotesExportMode mode) {
    switch (mode) {
      case NotesExportMode.all:
        return 'הכל';
      case NotesExportMode.byBook:
        return 'לפי ספר';
      case NotesExportMode.byDateRange:
        return 'טווח זמן';
      case NotesExportMode.manual:
        return 'בחירה ידנית';
    }
  }
}

import 'package:flutter/material.dart';
import '../repository/simple_notes_repository.dart';

/// דיאלוג ליצירת הערה חדשה
class CreateNoteDialog extends StatefulWidget {
  final String bookTitle;
  final int lineNumber;
  final String lineText;

  const CreateNoteDialog({
    super.key,
    required this.bookTitle,
    required this.lineNumber,
    required this.lineText,
  });

  @override
  State<CreateNoteDialog> createState() => _CreateNoteDialogState();
}

class _CreateNoteDialogState extends State<CreateNoteDialog> {
  final TextEditingController _contentController = TextEditingController();
  final SimpleNotesRepository _repository = SimpleNotesRepository.instance;
  bool _isLoading = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אנא הזן תוכן להערה')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _repository.createNote(
        bookTitle: widget.bookTitle,
        lineNumber: widget.lineNumber,
        lineText: widget.lineText,
        content: content,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // מחזיר true לציין שההערה נשמרה
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירת ההערה: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הוסף הערה לקטע זה'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // הצגת מיקום
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'שורה ${widget.lineNumber}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // שדה תוכן ההערה
          TextField(
            controller: _contentController,
            decoration: const InputDecoration(
              labelText: 'תוכן ההערה',
              hintText: 'הזן את ההערה שלך כאן...',
              border: OutlineInputBorder(),
            ),
            maxLines: 5,
            autofocus: true,
            enabled: !_isLoading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveNote,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('שמור'),
        ),
      ],
    );
  }
}

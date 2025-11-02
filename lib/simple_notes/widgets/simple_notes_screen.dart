import 'package:flutter/material.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import '../models/simple_note.dart';
import '../repository/simple_notes_repository.dart';

/// מסך הערות פשוט
///
/// מציג שתי כרטיסיות: הערות עם מיקום והערות ללא מיקום.
class SimpleNotesScreen extends StatefulWidget {
  final String? bookTitle;
  final Function(int)? onNavigateToLine;

  const SimpleNotesScreen({
    super.key,
    this.bookTitle,
    this.onNavigateToLine,
  });

  @override
  State<SimpleNotesScreen> createState() => _SimpleNotesScreenState();
}

class _SimpleNotesScreenState extends State<SimpleNotesScreen> {
  final SimpleNotesRepository _repository = SimpleNotesRepository.instance;

  List<SimpleNote> _locatedNotes = [];
  List<SimpleNote> _locationlessNotes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void didUpdateWidget(SimpleNotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bookTitle != oldWidget.bookTitle) {
      _loadNotes();
    }
  }

  Future<void> _loadNotes() async {
    if (widget.bookTitle == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final located = await _repository.getLocatedNotes(widget.bookTitle!);
      final locationless =
          await _repository.getLocationlessNotes(widget.bookTitle!);

      setState(() {
        _locatedNotes = located;
        _locationlessNotes = locationless;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת הערות: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_locatedNotes.isEmpty && _locationlessNotes.isEmpty) {
      return const Center(
        child: Text('אין הערות'),
      );
    }

    return ListView(
      children: [
        // הערות עם מיקום
        if (_locatedNotes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'הערות (${_locatedNotes.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          ..._locatedNotes
              .map((note) => _buildNoteCard(note, hasLocation: true)),
        ],

        // קו מפריד
        if (_locatedNotes.isNotEmpty && _locationlessNotes.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            height: 1,
            color: Theme.of(context).dividerColor,
          ),

        // הערות ללא מיקום
        if (_locationlessNotes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'הערות חסרות מיקום (${_locationlessNotes.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
          ..._locationlessNotes
              .map((note) => _buildNoteCard(note, hasLocation: false)),
        ],
      ],
    );
  }

  Widget _buildNoteCard(SimpleNote note, {required bool hasLocation}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: hasLocation ? () => _onNoteTapped(note) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // כותרת עם מיקום
              Row(
                children: [
                  Icon(
                    hasLocation ? Icons.book : Icons.help_outline,
                    size: 16,
                    color: hasLocation ? Colors.blue : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasLocation
                          ? '${note.bookTitle} - שורה ${note.lineNumber}'
                          : note.bookTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // תוכן ההערה
              Text(
                note.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // מידע נוסף
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 12,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(note.updatedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (!hasLocation) ...[
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _relocateNote(note),
                      icon: const Icon(Icons.location_on, size: 16),
                      label: const Text('מקם מחדש'),
                    ),
                  ],
                ],
              ),

              // מיקום קודם להערות ללא מיקום
              if (!hasLocation && note.firstWords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_off, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'מיקום קודם: ${note.firstWords.take(5).join(" ")}...',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _onNoteTapped(SimpleNote note) {
    // ניווט לשורה
    if (widget.onNavigateToLine != null) {
      widget.onNavigateToLine!(note.lineNumber);
    }

    // אין צורך לסגור - זו כרטיסייה בתוך TabBarView, לא דיאלוג
  }

  Future<void> _relocateNote(SimpleNote note) async {
    // בקשת מספר שורה חדש מהמשתמש
    final controller = TextEditingController(text: note.lineNumber.toString());

    final newLineNumber = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מיקום מחדש של הערה'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'הערה: ${note.content.substring(0, note.content.length > 50 ? 50 : note.content.length)}...'),
            const SizedBox(height: 16),
            const Text('מיקום קודם:'),
            Text(note.firstWords.take(5).join(' ') + '...',
                style: const TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'מספר שורה חדש',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              final lineNum = int.tryParse(controller.text);
              if (lineNum != null && lineNum > 0) {
                Navigator.of(context).pop(lineNum);
              }
            },
            child: const Text('מקם מחדש'),
          ),
        ],
      ),
    );

    if (newLineNumber == null || !mounted) return;

    // הצגת loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('טוען...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );
    }

    try {
      // קבלת טקסט השורה החדשה
      final bookText =
          await FileSystemData.instance.getBookText(note.bookTitle);
      final lines = bookText.split('\n');

      // הסרת loading
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (newLineNumber < 1 || newLineNumber > lines.length) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('מספר שורה לא תקין')),
          );
        }
        return;
      }

      final newLineText = lines[newLineNumber - 1];

      // מיקום מחדש
      await _repository.relocateNote(
        noteId: note.id,
        bookTitle: note.bookTitle,
        newLineNumber: newLineNumber,
        newLineText: newLineText,
      );

      // רענון הרשימה
      await _loadNotes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ההערה מוקמה מחדש בשורה $newLineNumber')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה במיקום מחדש: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

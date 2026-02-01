import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:path/path.dart' as path;

/// Dialog for adding a personal book to the library
class AddPersonalBookDialog extends StatefulWidget {
  const AddPersonalBookDialog({super.key});

  @override
  State<AddPersonalBookDialog> createState() => _AddPersonalBookDialogState();
}

class _AddPersonalBookDialogState extends State<AddPersonalBookDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  String? _selectedFilePath;
  bool _isProcessing = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'docx'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          // Auto-fill title from filename if empty
          if (_titleController.text.isEmpty) {
            final filename =
                path.basenameWithoutExtension(result.files.single.name);
            _titleController.text = filename;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בבחירת קובץ: $e')),
        );
      }
    }
  }

  Future<void> _addBook() async {
    if (!_formKey.currentState!.validate() || _selectedFilePath == null) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final fileSystemData = FileSystemData.instance;

      // Ensure personal folder exists
      await fileSystemData.ensurePersonalFolderExists();

      final personalPath = fileSystemData.getPersonalBooksPath();
      final title = _titleController.text.trim();
      final extension = path.extension(_selectedFilePath!);
      final destinationPath = path.join(personalPath, '$title$extension');

      // Copy file to personal folder
      final sourceFile = File(_selectedFilePath!);
      await sourceFile.copy(destinationPath);

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הספר האישי נוסף בהצלחה!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהוספת ספר: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'הוסף ספר אישי',
        textAlign: TextAlign.right,
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ספרים אישיים נשמרים בתיקייה נפרדת ולא יועברו למסד הנתונים.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'שם הספר',
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.right,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'נא להזין שם ספר';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isProcessing ? null : _pickFile,
                icon: const Icon(FluentIcons.folder_open_24_regular),
                label: Text(
                  _selectedFilePath == null
                      ? 'בחר קובץ (TXT או DOCX)'
                      : 'קובץ נבחר: ${path.basename(_selectedFilePath!)}',
                ),
              ),
              if (_selectedFilePath == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'נא לבחור קובץ',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _addBook,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('הוסף'),
        ),
      ],
    );
  }
}

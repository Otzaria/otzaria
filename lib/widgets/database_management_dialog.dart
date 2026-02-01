import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/widgets/restart_widget.dart';

/// Dialog for managing database operations (export/import)
class DatabaseManagementDialog extends StatefulWidget {
  const DatabaseManagementDialog({super.key});

  @override
  State<DatabaseManagementDialog> createState() =>
      _DatabaseManagementDialogState();
}

class _DatabaseManagementDialogState extends State<DatabaseManagementDialog> {
  bool _isProcessing = false;
  Map<String, dynamic>? _dbStats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await FileSystemData.instance.getDatabaseStats();
      if (mounted) {
        setState(() => _dbStats = stats);
      }
    } catch (e) {
      debugPrint('Error loading DB stats: $e');
    }
  }

  Future<void> _exportDatabase() async {
    setState(() => _isProcessing = true);

    try {
      final sqliteProvider =
          FileSystemData.instance.databaseProvider.sqliteProvider;

      // Check if database exists
      if (!await sqliteProvider.databaseExists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('מסד הנתונים עדיין לא נוצר'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Ask user where to save
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'שמור מסד נתונים',
        fileName: 'otzaria_backup_${DateTime.now().millisecondsSinceEpoch}.db',
      );

      if (result != null) {
        await sqliteProvider.exportDatabase(result);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('מסד הנתונים יוצא בהצלחה ל:\n$result'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בייצוא מסד נתונים: $e'),
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

  Future<void> _importDatabase() async {
    // Show warning dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אזהרה', textAlign: TextAlign.right),
        content: const Text(
          'ייבוא מסד נתונים ימחק את כל הנתונים הקיימים!\n'
          'האם אתה בטוח שברצונך להמשיך?',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('המשך'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      // Pick database file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (result != null && result.files.single.path != null) {
        final sourcePath = result.files.single.path!;

        // Verify it's a valid database file
        final file = File(sourcePath);
        if (!await file.exists()) {
          throw Exception('הקובץ לא נמצא');
        }

        final sqliteProvider =
            FileSystemData.instance.databaseProvider.sqliteProvider;
        await sqliteProvider.importDatabase(sourcePath);

        // Reload stats
        await _loadStats();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('מסד הנתונים יובא בהצלחה!'),
              backgroundColor: Colors.green,
            ),
          );

          // Close dialog and suggest restart
          Navigator.of(context).pop();

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('יבוא הושלם', textAlign: TextAlign.right),
              content: const Text(
                'מומלץ לאתחל את התוכנה כדי שהשינויים ייכנסו לתוקף.',
                textAlign: TextAlign.right,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('אחר כך'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    RestartWidget.restartApp(context);
                  },
                  child: const Text('אתחל כעת'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בייבוא מסד נתונים: $e'),
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
        'ניהול מסד נתונים',
        textAlign: TextAlign.right,
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Statistics
            if (_dbStats != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'סטטיסטיקות',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                          'סטטוס', _dbStats!['enabled'] ? 'פעיל' : 'לא פעיל'),
                      _buildStatRow(
                          'ספרים במסד נתונים', '${_dbStats!['books']}'),
                      _buildStatRow('קישורים', '${_dbStats!['links']}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Export button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _exportDatabase,
              icon: const Icon(FluentIcons.arrow_upload_24_regular),
              label: const Text('ייצא מסד נתונים'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'שמור עותק גיבוי של מסד הנתונים',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              textAlign: TextAlign.right,
            ),

            const SizedBox(height: 24),

            // Import button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _importDatabase,
              icon: const Icon(FluentIcons.arrow_download_24_regular),
              label: const Text('ייבא מסד נתונים'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'שחזר מסד נתונים מגיבוי (ימחק את הנתונים הקיימים!)',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.red,
              ),
              textAlign: TextAlign.right,
            ),

            if (_isProcessing) ...[
              const SizedBox(height: 16),
              const Center(
                child: CircularProgressIndicator(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('סגור'),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label),
        ],
      ),
    );
  }
}

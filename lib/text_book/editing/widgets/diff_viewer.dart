import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Widget for displaying side-by-side diff of original vs edited content
class DiffViewer extends StatelessWidget {
  final String originalContent;
  final String editedContent;
  final String title;

  const DiffViewer({
    super.key,
    required this.originalContent,
    required this.editedContent,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('השוואה - $title'),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Row(
        children: [
          // Original content (right side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    border: Border(
                      bottom:
                          BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: const Text(
                    'מקור',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      originalContent,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'TaameyAshkenaz',
                        height: 1.5,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Container(
            width: 1,
            color: Theme.of(context).dividerColor,
          ),

          // Edited content (left side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    border: Border(
                      bottom: BorderSide(
                          color: Colors.green.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: const Text(
                    'נערך',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      editedContent,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'TaameyAshkenaz',
                        height: 1.5,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a diff viewer dialog
void showDiffViewer({
  required BuildContext context,
  required String originalContent,
  required String editedContent,
  required String title,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => DiffViewer(
        originalContent: originalContent,
        editedContent: editedContent,
        title: title,
      ),
    ),
  );
}

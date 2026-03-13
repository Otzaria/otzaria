import 'package:flutter/material.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

/// Dialog that explains the personal books feature
class PersonalBooksInfoDialog extends StatelessWidget {
  const PersonalBooksInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final personalPath = FileSystemData.instance.getPersonalBooksPath();

    return AlertDialog(
      title: const Text(
        'אודות ספרים אישיים',
        textAlign: TextAlign.right,
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'מהם ספרים אישיים?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 8),
              const Text(
                'ספרים אישיים הם ספרים שאתה מוסיף בעצמך לספרייה. '
                'הם נשמרים בתיקייה נפרדת ולא יועברו למסד הנתונים.',
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              const Text(
                'יתרונות:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 4),
              _buildBulletPoint('שמירה על קבצים פרטיים'),
              _buildBulletPoint('אין צורך בסנכרון עם השרת'),
              _buildBulletPoint('שליטה מלאה על התוכן'),
              _buildBulletPoint('אפשרות לעריכה ישירה של הקבצים'),
              const SizedBox(height: 16),
              const Text(
                'מיקום התיקייה:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  personalPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'איך להוסיף ספר אישי?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 4),
              _buildBulletPoint('לחץ על כפתור "הוסף ספר אישי"'),
              _buildBulletPoint('בחר קובץ TXT או DOCX'),
              _buildBulletPoint('הזן שם לספר'),
              _buildBulletPoint('לחץ "הוסף"'),
              const SizedBox(height: 8),
              const Text(
                'לחלופין, העתק קבצים ישירות לתיקייה האישית.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('הבנתי'),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 4),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

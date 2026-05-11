import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

/// Tab שמציג מפרשים של ספר PDF בכרטסייה עצמאית.
/// חולק state עם sourceTab — מתעדכן אוטומטית כשהעמוד ב-PDF משתנה.
class PdfCommentatorsTab extends OpenedTab {
  final PdfBookTab sourceTab;

  PdfCommentatorsTab({required this.sourceTab})
      : super('מפרשים | ${sourceTab.title}');

  @override
  Map<String, dynamic> toJson() => {
        'title': title,
        'type': 'PdfCommentatorsTab',
        'isPinned': isPinned,
        // לא שומרים sourceTab כי לא ניתן לשחזר בקלות
      };
}

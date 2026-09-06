/// נושא המידע של קישור `otzaria://info/<topic>`.
///
/// קישור מסוג `info` אינו מנווט לשום מקום — הוא מחזיר דוח JSON שמוצג בפופאפ.
enum InfoTopic {
  app('app', 'מידע על התוכנה'),
  library('library', 'מידע על הספרייה'),
  folders('folders', 'תיקיות ספרים אישיים'),
  plugins('plugins', 'מידע על התוספים'),
  errors('errors', 'השגיאות האחרונות'),
  all('all', 'מידע מלא');

  const InfoTopic(this.slug, this.title);

  /// המזהה בכתובת ה-URI (`otzaria://info/<slug>`).
  final String slug;

  /// כותרת הפופאפ בעברית.
  final String title;

  /// מפענח מזהה נושא מכתובת. מחזיר null לנושא לא מוכר.
  static InfoTopic? fromSlug(String value) {
    switch (value.trim().toLowerCase()) {
      case 'app':
      case 'software':
      case 'version':
        return InfoTopic.app;
      case 'library':
      case 'books':
        return InfoTopic.library;
      case 'folders':
      case 'folder':
      case 'personal':
      case 'personal_books':
      case 'personal_folders':
      case 'custom_folders':
        return InfoTopic.folders;
      case 'plugins':
      case 'plugin':
        return InfoTopic.plugins;
      case 'errors':
      case 'error':
      case 'log':
      case 'logs':
        return InfoTopic.errors;
      case 'all':
        return InfoTopic.all;
      default:
        return null;
    }
  }

  /// הנושאים שנכללים בדוח עבור נושא מבוקש. `all` מרחיב לכל השאר.
  List<InfoTopic> get sections => this == InfoTopic.all
      ? const [
          InfoTopic.app,
          InfoTopic.library,
          InfoTopic.folders,
          InfoTopic.plugins,
          InfoTopic.errors,
        ]
      : [this];
}

/// עזרי סיווג לסוגי קישורים
class LinkTypes {
  /// מחזיר true אם סוג הקישור הוא פירוש או תרגום
  static bool isCommentaryOrTargum(String connectionType) {
    return connectionType == 'commentary' || connectionType == 'targum';
  }
}

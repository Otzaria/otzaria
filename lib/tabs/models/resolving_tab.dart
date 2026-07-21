import 'package:otzaria/tabs/models/tab.dart';

/// טאב מחזיק-מקום: נפתח מיידית עם מחוון טעינה בזמן שהיעד הסופי (למשל מיפוי
/// עמוד PDF של מסכת בבלי) נפתר ברקע, ואז מוחלף בו-במקום דרך ReplaceTab.
class ResolvingTab extends OpenedTab {
  /// טאב היעד החלופי — משמש לשמירה/שחזור/שכפול, ונסגר יחד עם הטאב.
  final OpenedTab fallbackTab;

  /// בונה את הטאב הסופי; בכשל או ביעד לא-זמין הקורא נופל ל-[fallbackTab].
  final Future<OpenedTab> Function() resolve;

  Future<OpenedTab>? _resolution;

  /// מבטיח ש-ReplaceTab נשלח פעם אחת גם אם מסך הטעינה נבנה מחדש.
  bool replaceDispatched = false;

  ResolvingTab({
    required this.fallbackTab,
    required this.resolve,
    String? dedupeKey,
  }) : super(fallbackTab.title, dedupeKey: dedupeKey);

  /// מתחיל את הרזולוציה (פעם אחת) ומחזיר את הטאב הסופי.
  /// בכשל מוחזר עותק טרי של טאב היעד החלופי.
  Future<OpenedTab> ensureResolved() => _resolution ??= _resolveOrFallback();

  Future<OpenedTab> _resolveOrFallback() async {
    try {
      return await resolve();
    } catch (_) {
      return OpenedTab.from(fallbackTab);
    }
  }

  @override
  OpenedTab clone() => OpenedTab.from(fallbackTab);

  @override
  void dispose() {
    fallbackTab.dispose();
    super.dispose();
  }

  @override
  Map<String, dynamic> toJson() => fallbackTab.toJson();
}

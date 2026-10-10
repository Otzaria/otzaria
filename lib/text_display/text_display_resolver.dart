import 'package:otzaria/text_display/models/text_display_layer.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';

/// פותר פרופיל מלא לחריץ נתון מתוך שכבות.
///
/// [layers] מסודרות מהספציפי לכללי (עקיפות הכרטיסייה → קובץ הספר → סוג
/// הספר → גלובלי). לכל שדה: עוברים על שרשרת הירושה של החריץ, ובכל חריץ על
/// השכבות לפי סדרן; הערך הראשון שאינו null מנצח. כלומר טלאי *מפורש* על
/// המפרשים (גם בשכבה כללית, כמו החרגת התנ"ך) גובר על ערך שהמפרשים היו
/// יורשים מהגוף — הכפתור בסרגל שולט בגוף, ולמפרשים כפתור משלהם.
class TextDisplayResolver {
  TextDisplayResolver._();

  static TextDisplayProfile resolve({
    required TextDisplaySlot slot,
    required List<TextDisplayLayer> layers,
    TextDisplayProfile root = TextDisplayProfile.defaults,
  }) {
    final chain = slot.inheritanceChain;
    return TextDisplayProfile(
      nikud: _first(layers, chain, (p) => p.nikud) ?? root.nikud,
      teamim: _first(layers, chain, (p) => p.teamim) ?? root.teamim,
      punctuation:
          _first(layers, chain, (p) => p.punctuation) ?? root.punctuation,
      holyName: _first(layers, chain, (p) => p.holyName) ?? root.holyName,
      anchorMarkers:
          _first(layers, chain, (p) => p.anchorMarkers) ?? root.anchorMarkers,
    );
  }

  static T? _first<T>(
    List<TextDisplayLayer> layers,
    List<TextDisplaySlot> chain,
    T? Function(TextDisplayPatch) pick,
  ) {
    for (final candidate in chain) {
      for (final layer in layers) {
        if (layer.isEmpty) continue;
        final value = pick(layer.patchFor(candidate));
        if (value != null) return value;
      }
    }
    return null;
  }
}

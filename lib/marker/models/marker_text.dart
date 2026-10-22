import 'package:characters/characters.dart';

/// קיצור בלי לחתוך תו לשניים (אמוג'י, אות עם ניקוד).
String truncateGraphemes(String text, int max) {
  if (text.length <= max) return text;
  final chars = text.characters;
  return chars.length > max ? chars.take(max).toString() : text;
}

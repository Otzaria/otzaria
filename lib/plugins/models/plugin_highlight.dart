/// מודל המייצג הדגשה צבעונית של שורה בטקסט, שנוצרה על ידי פלאגין.
class PluginHighlight {
  final String bookId;
  final int index;
  final String? color; // CSS color string, e.g. "#FFFF00"
  final String? label;
  final String pluginId;

  const PluginHighlight({
    required this.bookId,
    required this.index,
    this.color,
    this.label,
    required this.pluginId,
  });

  Map<String, dynamic> toJson() {
    return {
      'bookId': bookId,
      'index': index,
      'pluginId': pluginId,
      if (color != null) 'color': color,
      if (label != null) 'label': label,
    };
  }
}

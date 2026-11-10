import 'package:otzaria/plugins/models/plugin_when_condition.dart';

/// פריט שתוסף רושם בשורת הפקדים או בתפריט ההקשר.
abstract interface class PluginRegistryItem {
  String get id;
  PluginWhenCondition? get when;
  List<PluginRegistryItem> get children;
  Map<String, dynamic> toJson();
}

/// מסנן ספר של פריט (`bookTypes` / `bookSources`): רשימה ריקה = כל ספר, ואחרת
/// הערך של הספר חייב להיות בה. ספר לא ידוע (null) עובר רק מסנן ריק.
bool bookFilterAllows(List<String> allowed, String? value) =>
    allowed.isEmpty || (value != null && allowed.contains(value));

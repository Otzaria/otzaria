import 'package:otzaria/plugins/models/plugin_when_condition.dart';

/// פריט שתוסף רושם בשורת הפקדים או בתפריט ההקשר.
abstract interface class PluginRegistryItem {
  String get id;
  PluginWhenCondition? get when;
  List<PluginRegistryItem> get children;
  Map<String, dynamic> toJson();
}

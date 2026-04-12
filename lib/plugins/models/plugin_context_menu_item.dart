/// מודל המייצג פריט תפריט הקשר שנרשם על ידי פלאגין.
class PluginContextMenuItem {
  final String id;
  final String label;
  final String? icon;

  const PluginContextMenuItem({
    required this.id,
    required this.label,
    this.icon,
  });
}

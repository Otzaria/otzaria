import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// מתג "כלול ספרים אישיים" של האיתור. מקור יחיד לדיאלוג, לקישורים ולסיור —
/// ברירת מחדל נפרדת במסלול אחד מסננת ספרים אישיים בשקט כשהמתג מוצג דלוק.
class FindRefPersonalBooksSetting {
  FindRefPersonalBooksSetting._();

  static const String key = 'key-find-ref-include-personal-books';

  static bool load() =>
      Settings.getValue<bool>(key, defaultValue: true) ?? true;

  static Future<void> save(bool value) => Settings.setValue<bool>(key, value);
}

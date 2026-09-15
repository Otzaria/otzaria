/// נקודת החיבור בין המסך לבין מימוש המנוע וטבלאות הנתונים.
///
/// המימושים חיים תחת `engine/` ו-`data/` ונרשמים כאן פעם אחת; המסך אינו
/// תלוי בהם בזמן קומפילציה.
library;

import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';

abstract class TikkunDependencies {
  static TikkunEngine? engine;
  static TikkunDataSource? data;

  static bool get isReady => engine != null && data != null;

  static void register({
    required TikkunEngine engine,
    required TikkunDataSource data,
  }) {
    TikkunDependencies.engine = engine;
    TikkunDependencies.data = data;
  }
}

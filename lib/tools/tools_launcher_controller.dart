import 'package:flutter/foundation.dart';

/// נקודת אחיזה גלובלית לפתיחת פאנל הכלים.
///
/// הפאנל הוא מצב פנימי של `MainWindowScreen`, אבל נדרש לפתוח אותו גם מהקשרים
/// שאין להם `BuildContext` של המסך: גשר התוספים, קישורים עמוקים, קיצורי
/// מקלדת והסיור המודרך. אותו דפוס כמו `PluginPageLauncher.navigator`.
class ToolsLauncherController {
  ToolsLauncherController._();

  static final ToolsLauncherController instance = ToolsLauncherController._();

  /// נרשם על-ידי `MainWindowScreen`. `null` כשהמסך אינו מורכב.
  void Function()? opener;

  @visibleForTesting
  int openCount = 0;

  void open() {
    openCount++;
    opener?.call();
  }
}

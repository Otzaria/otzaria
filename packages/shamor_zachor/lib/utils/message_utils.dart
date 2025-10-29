import 'package:otzaria/core/scaffold_messenger.dart';

/// Utility for routing Shamor Zachor messages through the global UI messenger.
class ShamorZachorMessenger {
  const ShamorZachorMessenger._();

  static void showInfo(String message) {
    UiSnack.show(message);
  }

  static void showSuccess(String message) {
    UiSnack.showSuccess(message);
  }

  static void showError(String message) {
    UiSnack.showError(message);
  }
}

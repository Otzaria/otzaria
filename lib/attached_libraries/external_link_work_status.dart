import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/work_status/work_status_item.dart';

/// מזהה פריט חיווי העבודה של אינדקס הקישורים.
const kExternalLinkWorkStatusId = 'external_link_index';

/// 1520000 -> 1,520,000
String formatLinkCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// סך ההתקדמות של כל המסדים שנבנים כעת.
({int done, int total}) sumLinkBuildProgress(
  Map<String, ExternalLinkBuildProgress> progress,
) => (
  done: progress.values.fold(0, (sum, p) => sum + p.done),
  total: progress.values.fold(0, (sum, p) => sum + p.total),
);

/// פריט חיווי העבודה לבניית אינדקס הקישורים, עם אותם לחצני השהיה ומצב חסכוני
/// של אינדוקס הספרים.
WorkStatusItem externalLinkWorkStatusItem(
  Map<String, ExternalLinkBuildProgress> progress, {
  required bool isPaused,
  required bool isEconomy,
  required VoidCallback onTogglePause,
  required VoidCallback onToggleEconomy,
}) {
  final (:done, :total) = sumLinkBuildProgress(progress);
  return WorkStatusItem(
    id: kExternalLinkWorkStatusId,
    title: 'אינדוקס קישורים',
    message: isPaused ? 'האינדוקס מושהה' : 'הקישורים בתהליך אינדוקס',
    detail: 'התקדמות: ${formatLinkCount(done)}/${formatLinkCount(total)}',
    progress: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
    actions: [
      WorkStatusAction(
        label: isPaused ? 'המשך' : 'השהה',
        icon: isPaused
            ? FluentIcons.play_24_regular
            : FluentIcons.pause_24_regular,
        onPressed: onTogglePause,
      ),
      WorkStatusAction(
        label: 'מצב חסכוני',
        icon: FluentIcons.battery_saver_24_regular,
        tooltip: 'מאט את האינדוקס ומפחית את העומס על המחשב',
        emphasized: isEconomy,
        onPressed: onToggleEconomy,
      ),
    ],
  );
}

/// מציג את בניית אינדקס הקישורים בכרטיס חיווי העבודה, ומסיר אותו בסיומה.
class ExternalLinkWorkStatusReporter {
  ExternalLinkWorkStatusReporter({
    required this.repository,
    required this.upsert,
    required this.remove,
  }) : _listenable = Listenable.merge([
         repository.buildProgress,
         repository.buildPaused,
         repository.buildEconomy,
       ]) {
    _listenable.addListener(_update);
    _update();
  }

  final ExternalLinkRepository repository;
  final void Function(WorkStatusItem item) upsert;
  final void Function(String id) remove;
  final Listenable _listenable;
  bool _shown = false;

  void _update() {
    final progress = repository.buildProgress.value;
    if (progress.isEmpty) {
      if (_shown) remove(kExternalLinkWorkStatusId);
      _shown = false;
      return;
    }
    _shown = true;
    upsert(
      externalLinkWorkStatusItem(
        progress,
        isPaused: repository.buildPaused.value,
        isEconomy: repository.buildEconomy.value,
        onTogglePause: () => repository.buildPaused.value
            ? repository.resumeBuild()
            : repository.pauseBuild(),
        onToggleEconomy: () =>
            repository.setBuildEconomy(!repository.buildEconomy.value),
      ),
    );
  }

  void dispose() => _listenable.removeListener(_update);
}

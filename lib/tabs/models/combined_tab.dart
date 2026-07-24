import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// Represents a combined tab that displays two books side-by-side.
///
/// This tab wraps two existing tabs (right and left) and displays them
/// together in a split view. When closed, both underlying tabs are closed.
class CombinedTab extends OpenedTab {
  /// The tab displayed on the right side
  final OpenedTab rightTab;

  /// The tab displayed on the left side
  final OpenedTab leftTab;

  /// The split ratio between the two tabs (0.0-1.0)
  /// Represents how much of the screen the right tab takes
  double splitRatio;

  /// Creates a new instance of [CombinedTab].
  ///
  /// The [rightTab] and [leftTab] parameters represent the two tabs
  /// to be displayed side-by-side.
  CombinedTab({
    required this.rightTab,
    required this.leftTab,
    this.splitRatio = 0.5,
    bool isPinned = false,
  }) : super(
         'משולב: ${rightTab.title} | ${leftTab.title}',
         isPinned: isPinned,
       );

  /// Updates the title when tabs change
  void updateTitle() {
    title = 'משולב: ${rightTab.title} | ${leftTab.title}';
  }

  /// Cleanup when the tab is disposed
  /// This will also dispose both underlying tabs
  @override
  void dispose() {
    rightTab.dispose();
    leftTab.dispose();
    super.dispose();
  }

  /// Creates a new instance of [CombinedTab] from a JSON map.
  factory CombinedTab.fromJson(Map<String, dynamic> json) {
    OpenedTab decodeTab(Map<String, dynamic> map) {
      if (map['type'] == 'PdfCommentatorsTab') {
        return PdfCommentatorsTab.fromJson(map);
      }
      if (map['type'] == 'CommentatorsTab') {
        return CommentatorsTab.fromJson(map);
      }
      return OpenedTab.fromJson(map);
    }

    return CombinedTab(
      rightTab: decodeTab(castMap(json['rightTab'])),
      leftTab: decodeTab(castMap(json['leftTab'])),
      splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? 0.5,
      isPinned: json['isPinned'] ?? false,
    );
  }

  /// Converts the [CombinedTab] instance into a JSON map.
  @override
  Map<String, dynamic> toJson() {
    return {
      'rightTab': rightTab.toJson(),
      'leftTab': leftTab.toJson(),
      'splitRatio': splitRatio,
      'isPinned': isPinned,
      'type': 'CombinedTab',
    };
  }
}

import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// Represents a workspace in the application.
///
/// A `Workspace` object has a unique [id], a [name],
/// a list of [tabs], and the [activeTabIndex].
///
/// This class is immutable - use [copyWith] to create modified copies.
class Workspace extends Equatable {
  final String id;
  final String name;
  final List<OpenedTab> tabs;
  final int activeTabIndex;

  Workspace({
    String? id,
    required this.name,
    required this.tabs,
    this.activeTabIndex = 0,
  }) : id = id ?? _generateId();

  static int _idCounter = 0;

  /// Generates a unique ID using monotonic counter + microsecond timestamp.
  /// The counter guarantees uniqueness even when called multiple times within
  /// the same microsecond (e.g. in tests or fast programmatic creation).
  static String _generateId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
  }

  /// Creates a copy of this workspace with the given fields replaced.
  Workspace copyWith({
    String? name,
    List<OpenedTab>? tabs,
    int? activeTabIndex,
  }) {
    return Workspace(
      id: id, // ID remains the same
      name: name ?? this.name,
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }

  factory Workspace.fromJson(Map<String, dynamic> json) {
    OpenedTab? decodeTab(Map<String, dynamic> map) {
      if (map['type'] == 'PdfCommentatorsTab') return null;
      if (map['type'] == 'CommentatorsTab') {
        return CommentatorsTab.fromJson(map);
      }
      return OpenedTab.fromJson(map);
    }

    return Workspace(
      id: json['id'] as String?,
      name: json['name'] as String,
      tabs:
          (json['tabs'] as List?)
              ?.map((raw) => decodeTab(castMap(raw)))
              .whereType<OpenedTab>()
              .toList() ??
          [],
      activeTabIndex: json['currentTab'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final persistedTabs = <OpenedTab>[];
    var remappedIndex = 0;
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i] is PdfCommentatorsTab) continue;
      if (i <= activeTabIndex) remappedIndex = persistedTabs.length;
      persistedTabs.add(tabs[i]);
    }
    final safeIndex = persistedTabs.isEmpty
        ? 0
        : remappedIndex.clamp(0, persistedTabs.length - 1);
    return {
      'id': id,
      'name': name,
      'tabs': persistedTabs.map((tab) => tab.toJson()).toList(),
      'currentTab': safeIndex,
    };
  }

  @override
  List<Object?> get props => [id, name, tabs, activeTabIndex];
}

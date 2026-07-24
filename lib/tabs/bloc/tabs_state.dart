import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// מצב הצגת 2 ספרים זה לצד זה
class SideBySideMode extends Equatable {
  final int leftTabIndex;
  final int rightTabIndex;
  final double splitRatio; // 0.0-1.0, כמה מהמסך תופס הספר הימני

  const SideBySideMode({
    required this.leftTabIndex,
    required this.rightTabIndex,
    this.splitRatio = 0.5,
  });

  SideBySideMode copyWith({
    int? leftTabIndex,
    int? rightTabIndex,
    double? splitRatio,
  }) {
    return SideBySideMode(
      leftTabIndex: leftTabIndex ?? this.leftTabIndex,
      rightTabIndex: rightTabIndex ?? this.rightTabIndex,
      splitRatio: splitRatio ?? this.splitRatio,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'leftTabIndex': leftTabIndex,
      'rightTabIndex': rightTabIndex,
      'splitRatio': splitRatio,
    };
  }

  factory SideBySideMode.fromJson(Map<String, dynamic> json) {
    return SideBySideMode(
      leftTabIndex: json['leftTabIndex'] as int,
      rightTabIndex: json['rightTabIndex'] as int,
      splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? 0.5,
    );
  }

  @override
  List<Object?> get props => [leftTabIndex, rightTabIndex, splitRatio];
}

class TabsState extends Equatable {
  final List<OpenedTab> tabs;
  final int currentTabIndex;
  final int updateCounter;
  final SideBySideMode? sideBySideMode;

  const TabsState({
    required this.tabs,
    required this.currentTabIndex,
    this.updateCounter = 0,
    this.sideBySideMode,
  });

  factory TabsState.initial() {
    return const TabsState(
      tabs: [],
      currentTabIndex: 0,
      updateCounter: 0,
      sideBySideMode: null,
    );
  }

  TabsState copyWith({
    List<OpenedTab>? tabs,
    int? currentTabIndex,
    bool forceUpdate = false,
    SideBySideMode? sideBySideMode,
    bool clearSideBySide = false,
  }) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      updateCounter: forceUpdate ? updateCounter + 1 : updateCounter,
      sideBySideMode: clearSideBySide
          ? null
          : (sideBySideMode ?? this.sideBySideMode),
    );
  }

  bool get hasOpenTabs => tabs.isNotEmpty;
  OpenedTab? get currentTab => hasOpenTabs ? tabs[currentTabIndex] : null;
  bool get isSideBySideMode => sideBySideMode != null;

  @override
  List<Object?> get props => [
    tabs,
    currentTabIndex,
    updateCounter,
    sideBySideMode,
  ];
}

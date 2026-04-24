import 'package:equatable/equatable.dart';
import 'package:otzaria/product_tour/models/product_tour_models.dart';

class ProductTourState extends Equatable {
  final bool isBootstrapped;
  final bool isLibraryReady;
  final ProductTourStatus status;
  final int lastPersistedStepIndex;
  final int? activeIntroStepIndex;
  final LiveTipId? activeLiveTipId;
  final Set<LiveTipId> shownTips;
  final Set<LiveTipId> resolvedTips;

  const ProductTourState({
    required this.isBootstrapped,
    required this.isLibraryReady,
    required this.status,
    required this.lastPersistedStepIndex,
    required this.activeIntroStepIndex,
    required this.activeLiveTipId,
    required this.shownTips,
    required this.resolvedTips,
  });

  factory ProductTourState.initial() {
    return const ProductTourState(
      isBootstrapped: false,
      isLibraryReady: false,
      status: ProductTourStatus.unseen,
      lastPersistedStepIndex: 0,
      activeIntroStepIndex: null,
      activeLiveTipId: null,
      shownTips: <LiveTipId>{},
      resolvedTips: <LiveTipId>{},
    );
  }

  bool get hasActiveIntroTour => activeIntroStepIndex != null;
  bool get hasActiveLiveTip => activeLiveTipId != null;
  bool get hasActiveOverlay => hasActiveIntroTour || hasActiveLiveTip;

  ProductTourState copyWith({
    bool? isBootstrapped,
    bool? isLibraryReady,
    ProductTourStatus? status,
    int? lastPersistedStepIndex,
    int? activeIntroStepIndex,
    LiveTipId? activeLiveTipId,
    Set<LiveTipId>? shownTips,
    Set<LiveTipId>? resolvedTips,
    bool clearIntro = false,
    bool clearLiveTip = false,
  }) {
    return ProductTourState(
      isBootstrapped: isBootstrapped ?? this.isBootstrapped,
      isLibraryReady: isLibraryReady ?? this.isLibraryReady,
      status: status ?? this.status,
      lastPersistedStepIndex:
          lastPersistedStepIndex ?? this.lastPersistedStepIndex,
      activeIntroStepIndex: clearIntro
          ? null
          : (activeIntroStepIndex ?? this.activeIntroStepIndex),
      activeLiveTipId:
          clearLiveTip ? null : (activeLiveTipId ?? this.activeLiveTipId),
      shownTips: shownTips ?? this.shownTips,
      resolvedTips: resolvedTips ?? this.resolvedTips,
    );
  }

  @override
  List<Object?> get props => [
        isBootstrapped,
        isLibraryReady,
        status,
        lastPersistedStepIndex,
        activeIntroStepIndex,
        activeLiveTipId,
        shownTips.map((tip) => tip.name).toList()..sort(),
        resolvedTips.map((tip) => tip.name).toList()..sort(),
      ];
}

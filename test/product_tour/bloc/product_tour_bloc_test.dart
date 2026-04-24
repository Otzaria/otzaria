import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/product_tour/product_tour_exports.dart';

class InMemoryProductTourRepository extends ProductTourRepository {
  ProductTourStatus storedStatus;
  int storedLastStep;
  Set<LiveTipId> storedShownTips;
  Set<LiveTipId> storedResolvedTips;

  InMemoryProductTourRepository({
    this.storedStatus = ProductTourStatus.unseen,
    this.storedLastStep = 0,
    Set<LiveTipId>? storedShownTips,
    Set<LiveTipId>? storedResolvedTips,
  })  : storedShownTips = storedShownTips ?? <LiveTipId>{},
        storedResolvedTips = storedResolvedTips ?? <LiveTipId>{};

  @override
  Future<ProductTourStatus> loadStatus() async => storedStatus;

  @override
  Future<void> saveStatus(ProductTourStatus status) async {
    storedStatus = status;
  }

  @override
  Future<int> loadLastStep() async => storedLastStep;

  @override
  Future<void> saveLastStep(int stepIndex) async {
    storedLastStep = stepIndex;
  }

  @override
  Future<Set<LiveTipId>> loadShownTips() async => storedShownTips;

  @override
  Future<Set<LiveTipId>> loadResolvedTips() async => storedResolvedTips;

  @override
  Future<void> saveShownTips(Set<LiveTipId> tipIds) async {
    storedShownTips = tipIds;
  }

  @override
  Future<void> saveResolvedTips(Set<LiveTipId> tipIds) async {
    storedResolvedTips = tipIds;
  }

  @override
  Future<void> resetAll() async {
    storedStatus = ProductTourStatus.unseen;
    storedLastStep = 0;
    storedShownTips = <LiveTipId>{};
    storedResolvedTips = <LiveTipId>{};
  }
}

void main() {
  group('ProductTourBloc', () {
    blocTest<ProductTourBloc, ProductTourState>(
      'auto starts intro only after bootstrap and library ready',
      build: () => ProductTourBloc(
        repository: InMemoryProductTourRepository(),
      ),
      act: (bloc) async {
        bloc.add(const BootstrapTour());
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          RecordInteraction(
            TourInteraction(
              type: TourInteractionType.libraryReady,
            ),
          ),
        );
      },
      expect: () => [
        isA<ProductTourState>().having(
          (state) => state.isBootstrapped,
          'isBootstrapped',
          true,
        ),
        isA<ProductTourState>()
            .having(
              (state) => state.isLibraryReady,
              'isLibraryReady',
              true,
            )
            .having(
              (state) => state.activeIntroStepIndex,
              'activeIntroStepIndex',
              null,
            ),
        isA<ProductTourState>().having(
          (state) => state.activeIntroStepIndex,
          'activeIntroStepIndex',
          0,
        ),
      ],
    );

    blocTest<ProductTourBloc, ProductTourState>(
      'dismiss intro marks status as dismissed',
      build: () => ProductTourBloc(
        repository: InMemoryProductTourRepository(),
      ),
      act: (bloc) async {
        bloc.add(const BootstrapTour());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const StartIntroTour(manual: true));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const DismissActiveOverlay());
      },
      expect: () => [
        isA<ProductTourState>().having(
          (state) => state.isBootstrapped,
          'isBootstrapped',
          true,
        ),
        isA<ProductTourState>().having(
          (state) => state.activeIntroStepIndex,
          'activeIntroStepIndex',
          0,
        ),
        isA<ProductTourState>()
            .having(
              (state) => state.status,
              'status',
              ProductTourStatus.dismissed,
            )
            .having(
              (state) => state.activeIntroStepIndex,
              'activeIntroStepIndex',
              null,
            ),
      ],
    );

    blocTest<ProductTourBloc, ProductTourState>(
      'dictionary tip is shown once and not reopened after resolve',
      build: () => ProductTourBloc(
        repository: InMemoryProductTourRepository(
          storedStatus: ProductTourStatus.dismissed,
        ),
      ),
      act: (bloc) async {
        bloc.add(const BootstrapTour());
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          RecordInteraction(
            TourInteraction(
              type: TourInteractionType.textSelected,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          RecordInteraction(
            TourInteraction(
              type: TourInteractionType.textSelected,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(const DismissActiveOverlay());
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          RecordInteraction(
            TourInteraction(
              type: TourInteractionType.dictionaryUsed,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          RecordInteraction(
            TourInteraction(
              type: TourInteractionType.textSelected,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          RecordInteraction(
            TourInteraction(
              type: TourInteractionType.textSelected,
            ),
          ),
        );
      },
      expect: () => [
        isA<ProductTourState>().having(
          (state) => state.status,
          'status',
          ProductTourStatus.dismissed,
        ),
        isA<ProductTourState>().having(
          (state) => state.activeLiveTipId,
          'activeLiveTipId',
          LiveTipId.dictionaryContextMenuHint,
        ),
        isA<ProductTourState>().having(
          (state) => state.activeLiveTipId,
          'activeLiveTipId',
          null,
        ),
        isA<ProductTourState>().having(
          (state) => state.resolvedTips.contains(
            LiveTipId.dictionaryContextMenuHint,
          ),
          'resolved dictionary tip',
          true,
        ),
      ],
      verify: (bloc) {
        expect(
          bloc.state.activeLiveTipId,
          isNull,
        );
        expect(
          bloc.state.resolvedTips.contains(
            LiveTipId.dictionaryContextMenuHint,
          ),
          isTrue,
        );
      },
    );
  });
}

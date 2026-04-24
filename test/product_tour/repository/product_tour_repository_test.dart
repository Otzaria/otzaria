import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/product_tour/product_tour_exports.dart';

import '../../unit/mocks/mock_settings_wrapper.mocks.dart';

void main() {
  group('ProductTourRepository', () {
    late MockSettingsWrapper mockSettingsWrapper;
    late ProductTourRepository repository;

    setUp(() {
      mockSettingsWrapper = MockSettingsWrapper();
      repository = ProductTourRepository(settings: mockSettingsWrapper);
    });

    test('loadStatus returns unseen when nothing is stored', () async {
      when(
        mockSettingsWrapper.getValue<String>(
          ProductTourRepository.keyProductTourStatus,
          defaultValue: ProductTourStatus.unseen.name,
        ),
      ).thenReturn(ProductTourStatus.unseen.name);

      final status = await repository.loadStatus();

      expect(status, ProductTourStatus.unseen);
    });

    test('loadShownTips decodes stored tip ids', () async {
      when(
        mockSettingsWrapper.getValue<String>(
          ProductTourRepository.keyLiveTipsShown,
          defaultValue: '[]',
        ),
      ).thenReturn('["dictionaryContextMenuHint","commentaryHint"]');

      final shownTips = await repository.loadShownTips();

      expect(
        shownTips,
        {
          LiveTipId.dictionaryContextMenuHint,
          LiveTipId.commentaryHint,
        },
      );
    });

    test('saveResolvedTips stores a sorted JSON payload', () async {
      await repository.saveResolvedTips(
        {
          LiveTipId.dictionaryContextMenuHint,
          LiveTipId.sideBySideSuggestion,
        },
      );

      verify(
        mockSettingsWrapper.setValue<String>(
          ProductTourRepository.keyLiveTipsResolved,
          '["dictionaryContextMenuHint","sideBySideSuggestion"]',
        ),
      ).called(1);
    });
  });
}

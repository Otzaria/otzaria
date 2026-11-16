import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_event.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_state.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';

export 'semantic_search_event.dart';
export 'semantic_search_state.dart';

/// מנהל את מצב הזמינות וההורדה של החיפוש הסמנטי עבור הממשק.
///
/// הפעולות עצמן ב-[SemanticSearchRepository]; ה-bloc מתרגם אירועי משתמש
/// ומשקף את [SemanticSearchRepository.availabilityChanges].
class SemanticSearchBloc
    extends Bloc<SemanticSearchEvent, SemanticSearchState> {
  final SemanticSearchRepository repository;
  StreamSubscription<Object?>? _subscription;
  bool _coverageWanted = false;

  SemanticSearchBloc({required this.repository})
    : super(
        SemanticSearchState(
          availability: repository.availability,
          quantization: repository.quantization,
          modelChoice: repository.modelChoice,
          activeModelChoice: repository.activeModelChoice,
        ),
      ) {
    on<SemanticSearchStarted>(_onStarted);
    on<SemanticUpdateFrequencyChanged>(
      (event, emit) => repository.setUpdateFrequency(event.frequency),
    );
    on<SemanticDownloadRequested>(
      (event, emit) => repository.enableAndDownload(),
    );
    on<SemanticDownloadCancelRequested>(
      (event, emit) => repository.cancelDownload(),
    );
    on<SemanticQuantizationChanged>(_onQuantizationChanged);
    on<SemanticModelChoiceChanged>((event, emit) async {
      emit(state.copyWith(modelChoice: event.modelChoice));
      await repository.setModelChoice(event.modelChoice);
      emit(
        state.copyWith(
          modelChoice: repository.modelChoice,
          activeModelChoice: repository.activeModelChoice,
          availability: repository.availability,
        ),
      );
    });
    on<SemanticDataRemovalRequested>(_onRemovalRequested);
    on<SemanticAvailabilityUpdated>((event, emit) async {
      emit(
        state.copyWith(
          availability: event.availability,
          modelChoice: repository.modelChoice,
          activeModelChoice: repository.activeModelChoice,
        ),
      );
      await _loadCoverageIfWanted(emit);
    });
    on<SemanticCoveredBooksRequested>((event, emit) async {
      _coverageWanted = true;
      await _loadCoverageIfWanted(emit);
    });
  }

  Future<void> _loadCoverageIfWanted(Emitter<SemanticSearchState> emit) async {
    if (!_coverageWanted || !state.availability.isUsable) return;
    final covered = await repository.loadCoveredBookFilePaths();
    if (covered != null) emit(state.copyWith(coveredBookFilePaths: covered));
  }

  Future<void> _onStarted(
    SemanticSearchStarted event,
    Emitter<SemanticSearchState> emit,
  ) async {
    _subscription ??= repository.availabilityChanges.listen(
      (availability) => add(SemanticAvailabilityUpdated(availability)),
    );
    final availability = await repository.refresh();
    emit(state.copyWith(availability: availability));
    await _loadCoverageIfWanted(emit);
  }

  Future<void> _onQuantizationChanged(
    SemanticQuantizationChanged event,
    Emitter<SemanticSearchState> emit,
  ) async {
    emit(state.copyWith(quantization: event.quantization));
    await repository.setQuantization(event.quantization);
  }

  Future<void> _onRemovalRequested(
    SemanticDataRemovalRequested event,
    Emitter<SemanticSearchState> emit,
  ) async {
    emit(state.copyWith(isRemoving: true));
    await repository.removeData();
    emit(
      state.copyWith(isRemoving: false, availability: repository.availability),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

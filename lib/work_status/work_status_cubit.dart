import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/work_status/work_status_item.dart';

class WorkStatusState {
  final Map<String, WorkStatusItem> items;
  final bool isDismissed;

  const WorkStatusState({
    this.items = const {},
    this.isDismissed = false,
  });

  bool get hasActiveItems => items.isNotEmpty;

  List<WorkStatusItem> get orderedItems => items.values.toList();

  WorkStatusState copyWith({
    Map<String, WorkStatusItem>? items,
    bool? isDismissed,
  }) {
    return WorkStatusState(
      items: items ?? this.items,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkStatusState &&
          runtimeType == other.runtimeType &&
          _mapsEqual(items, other.items) &&
          isDismissed == other.isDismissed;

  @override
  int get hashCode {
    var h = isDismissed.hashCode;
    for (final entry in items.entries) {
      h ^= Object.hash(entry.key, entry.value);
    }
    return h;
  }

  static bool _mapsEqual(
    Map<String, WorkStatusItem> a,
    Map<String, WorkStatusItem> b,
  ) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}

class WorkStatusCubit extends Cubit<WorkStatusState> {
  WorkStatusCubit() : super(const WorkStatusState());

  void upsert(WorkStatusItem item) {
    final isNewItem = !state.items.containsKey(item.id);
    final newItems = Map<String, WorkStatusItem>.from(state.items)
      ..[item.id] = item;
    emit(
      state.copyWith(
        items: newItems,
        isDismissed: isNewItem ? false : state.isDismissed,
      ),
    );
  }

  void remove(String id) {
    final newItems = Map<String, WorkStatusItem>.from(state.items)..remove(id);
    emit(
      state.copyWith(
        items: newItems,
        isDismissed: newItems.isEmpty ? false : state.isDismissed,
      ),
    );
  }

  void dismiss() {
    if (!state.isDismissed) {
      emit(state.copyWith(isDismissed: true));
    }
  }
}

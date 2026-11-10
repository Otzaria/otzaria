import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/work_status/work_status_item.dart';

class WorkStatusState {
  final Map<String, WorkStatusItem> items;
  final bool isDismissed;

  /// פריטים שהכרטיס שלהם מצומצם לגלולה בשורת הכותרת.
  final Set<String> collapsedIds;

  const WorkStatusState({
    this.items = const {},
    this.isDismissed = false,
    this.collapsedIds = const {},
  });

  bool get hasActiveItems => items.isNotEmpty;

  List<WorkStatusItem> get orderedItems => items.values.toList();

  /// הפריטים שמוצגים בכרטיס.
  List<WorkStatusItem> get cardItems => [
    for (final item in items.values)
      if (!collapsedIds.contains(item.id)) item,
  ];

  /// הפריטים שמוצגים כגלולה בשורת הכותרת.
  List<WorkStatusItem> get collapsedItems => [
    for (final item in items.values)
      if (collapsedIds.contains(item.id)) item,
  ];

  WorkStatusState copyWith({
    Map<String, WorkStatusItem>? items,
    bool? isDismissed,
    Set<String>? collapsedIds,
  }) {
    return WorkStatusState(
      items: items ?? this.items,
      isDismissed: isDismissed ?? this.isDismissed,
      collapsedIds: collapsedIds ?? this.collapsedIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkStatusState &&
          runtimeType == other.runtimeType &&
          _mapsEqual(items, other.items) &&
          isDismissed == other.isDismissed &&
          setEquals(collapsedIds, other.collapsedIds);

  @override
  int get hashCode {
    var h = isDismissed.hashCode ^ Object.hashAllUnordered(collapsedIds);
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

  final Map<String, Timer> _autoDismissTimers = {};
  final Map<String, Timer> _collapseTimers = {};

  void upsert(WorkStatusItem item) {
    final previous = state.items[item.id];
    _autoDismissTimers.remove(item.id)?.cancel();
    final autoDismissAfter = item.autoDismissAfter;
    if (autoDismissAfter != null) {
      _autoDismissTimers[item.id] = Timer(
        autoDismissAfter,
        () => remove(item.id),
      );
    }
    _scheduleCollapse(item, previous);
    // פריט שחדל להיות בר־כיווץ (נכשל, ממתין להחלטה) חייב להיות גלוי.
    final needsAttention =
        state.collapsedIds.contains(item.id) &&
        previous?.collapseAfter != null &&
        item.collapseAfter == null;
    final newItems = Map<String, WorkStatusItem>.from(state.items)
      ..[item.id] = item;
    emit(
      state.copyWith(
        items: newItems,
        collapsedIds: needsAttention
            ? ({...state.collapsedIds}..remove(item.id))
            : null,
        isDismissed: previous == null || needsAttention
            ? false
            : state.isDismissed,
      ),
    );
  }

  /// הספירה מתחילה רק כשהפריט נכנס או הופך לבר־כיווץ, ולא בכל עדכון התקדמות.
  void _scheduleCollapse(WorkStatusItem item, WorkStatusItem? previous) {
    final after = item.collapseAfter;
    if (after == null) {
      _collapseTimers.remove(item.id)?.cancel();
    } else if (previous?.collapseAfter == null) {
      _collapseTimers[item.id]?.cancel();
      _collapseTimers[item.id] = Timer(after, () => _collapse({item.id}));
    }
  }

  void _collapse(Set<String> ids) {
    for (final id in ids) {
      _collapseTimers.remove(id)?.cancel();
    }
    final target = ids.where(state.items.containsKey).toSet();
    if (state.collapsedIds.containsAll(target)) return;
    emit(state.copyWith(collapsedIds: {...state.collapsedIds, ...target}));
  }

  /// פותח מחדש את הכרטיס של פריט מצומצם; הוא נשאר פתוח עד סגירה ידנית.
  void expand(String id) {
    if (!state.collapsedIds.contains(id)) return;
    emit(
      state.copyWith(
        collapsedIds: {...state.collapsedIds}..remove(id),
        isDismissed: false,
      ),
    );
  }

  void remove(String id) {
    _autoDismissTimers.remove(id)?.cancel();
    _collapseTimers.remove(id)?.cancel();
    final newItems = Map<String, WorkStatusItem>.from(state.items)..remove(id);
    emit(
      state.copyWith(
        items: newItems,
        collapsedIds: {...state.collapsedIds}..remove(id),
        isDismissed: newItems.isEmpty ? false : state.isDismissed,
      ),
    );
  }

  @override
  Future<void> close() {
    for (final timer in [
      ..._autoDismissTimers.values,
      ..._collapseTimers.values,
    ]) {
      timer.cancel();
    }
    _autoDismissTimers.clear();
    _collapseTimers.clear();
    return super.close();
  }

  /// סוגר את הכרטיס: פריט עם גלולה מצטמצם אליה, והשאר מוסתרים עד פריט חדש.
  void dismiss() {
    if (state.isDismissed) return;
    _collapse({
      for (final item in state.items.values)
        if (item.chipLabel != null) item.id,
    });
    emit(state.copyWith(isDismissed: true));
  }
}

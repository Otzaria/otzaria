// מקליט עדכוני סמנטיקה — בדיוק מה שהמסגרת שולחת למנוע — ומריץ עליהם מודל
// של גשר הנגישות של Windows (accessibility_bridge.cc + ui::AXTree), כדי
// שבדיקת widget רגילה, בלי קורא מסך, תתפוס עדכון פגום ברגע שהוא נשלח:
//
// * קריסה (`isCrash`): `CreateRemoveReparentedNodesUpdate` מוחק ילד שעבר אב
//   מעותק של האב הקודם. ילד שרשום פעמיים ברשימות הממתינות (תחת שני אבות,
//   או פעמיים באותה רשימה) נמחק פעם שנייה ב-`erase(end())` — השחתת ערימה
//   (issue #3336). גם שורש שנרשם כילד של צומת אחר (`child->parent()` ריק).
// * דחייה: `ui::AXTree` דוחה את העדכון (`will not be in the tree and is not
//   the new root`, `Nodes left pending by the update` וכו') והעץ שבצד
//   Windows מתנתק מעץ המסגרת (issue #1399). כשהשלב הראשון (הסרת ילדים
//   שעברו אב) נדחה, הגשר אינו מנקה את העדכונים הממתינים והם מצטברים לעדכון
//   הבא — גם זה ממודל כאן.
//
// שימוש: בקובץ הבדיקה, לפני `testWidgets`, ליצור את ה-binding —
// `SemanticsRecordingBinding.ensure()` — ולהפעיל סמנטיקה עם
// `tester.ensureSemantics()`. אחרי הפעולה הנבדקת, `recorder.violations` ריק
// פירושו שכל העדכונים היו תקינים.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// צומת כפי שנשלח למנוע בקריאת `updateNode` אחת.
class RecordedSemanticsNode {
  RecordedSemanticsNode({
    required this.id,
    required this.label,
    required this.tooltip,
    required this.traversalParent,
    required this.childrenInTraversalOrder,
  });

  final int id;
  final String label;
  final String tooltip;

  /// מזהה האב בסדר המעבר, או -1 כשאין (כפי שנשלח למנוע).
  final int traversalParent;
  final List<int> childrenInTraversalOrder;

  @override
  String toString() =>
      'SemanticsNode#$id label="$label" tooltip="$tooltip" '
      'traversalParent=$traversalParent children=$childrenInTraversalOrder';
}

/// עדכון אחד שהמנוע היה דוחה או קורס עליו, והסיבה במילותיו.
class SemanticsUpdateViolation {
  SemanticsUpdateViolation(
    this.updateIndex,
    this.message,
    this.node, {
    this.isCrash = false,
  });

  /// מספרו הסידורי של העדכון מתחילת ההקלטה (החל מ-1).
  final int updateIndex;
  final String message;
  final RecordedSemanticsNode node;

  /// המנוע ב-release ניגש לזיכרון לא תקין (ולא רק דוחה את העדכון).
  final bool isCrash;

  @override
  String toString() =>
      '[update $updateIndex]${isCrash ? ' CRASH' : ''} $message\n    $node';
}

/// מודל של העץ בצד המנוע — ילדים בסדר מעבר בלבד, כמו הגשר.
class SemanticsUpdateRecorder {
  final Set<int> _nodes = {};
  final Map<int, List<int>> _children = {};
  final Map<int, int> _parentOf = {};
  int? _root;

  /// `pending_semantics_node_updates_` של הגשר — נשמר כשהשלב הראשון נכשל.
  final Map<int, RecordedSemanticsNode> _pending = {};
  int _updates = 0;

  /// כל העדכונים שהמנוע היה דוחה או קורס עליהם.
  final List<SemanticsUpdateViolation> violations = [];

  /// מנקה את המודל ואת הממצאים — לתחילת תרחיש חדש באותו קובץ בדיקה.
  void reset() {
    _nodes.clear();
    _children.clear();
    _parentOf.clear();
    _root = null;
    _pending.clear();
    _updates = 0;
    violations.clear();
  }

  void _violation(
    String message,
    RecordedSemanticsNode node, {
    bool crash = false,
  }) => violations.add(
    SemanticsUpdateViolation(_updates, message, node, isCrash: crash),
  );

  /// מריץ על המודל עדכון אחד, כפי שהמנוע מקבל אותו מ-`updateSemantics`.
  void apply(List<RecordedSemanticsNode> update) {
    _updates++;
    for (final n in update) {
      _pending[n.id] = n;
    }
    if (!_removeReparentedNodes()) return;
    _applyPendingUpdates();
    _pending.clear();
  }

  /// `CreateRemoveReparentedNodesUpdate` ואחריו `Unserialize` של התוצאה.
  /// מחזיר false כשה-AXTree דחה את השלב — אז הגשר יוצא בלי לנקות.
  bool _removeReparentedNodes() {
    final removals = <int, List<int>>{};
    final movers = <int, RecordedSemanticsNode>{};
    for (final node in _pending.values) {
      for (final child in node.childrenInTraversalOrder) {
        if (!_nodes.contains(child)) continue;
        final parent = _parentOf[child];
        if (parent == null) {
          _violation(
            'root $child listed as a child of ${node.id}: '
            'child->parent() is null (accessibility_bridge.cc:229)',
            node,
            crash: true,
          );
          continue;
        }
        if (parent == node.id) continue;
        final copy = removals.putIfAbsent(
          parent,
          () => List.of(_children[parent] ?? const <int>[]),
        );
        if (!copy.remove(child)) {
          _violation(
            '$child moves from $parent but was already erased from its copy '
            '(listed again after ${movers[child]?.id}): erase(end()) '
            '(accessibility_bridge.cc:249)',
            node,
            crash: true,
          );
          continue;
        }
        movers[child] = node;
      }
    }
    if (removals.isEmpty) return true;

    // ה-AXTree מעבד את האבות בסדר של unordered_map; אב שנמצא בתת-עץ שאב אחר
    // מסיר נדחה כשהוא מגיע אחריו — כאן מניחים את הסדר הגרוע.
    final destroyed = <int>{};
    for (final entry in removals.entries) {
      for (final child in _children[entry.key] ?? const <int>[]) {
        if (!entry.value.contains(child)) _collectSubtree(child, destroyed);
      }
    }
    for (final parent in removals.keys) {
      if (!destroyed.contains(parent)) continue;
      final mover = movers.entries.firstWhere(
        (e) => _parentOf[e.key] == parent,
        orElse: () => movers.entries.first,
      );
      _violation(
        'remove-reparented update fails: $parent will not be in the tree '
        '(an ancestor of it is reparented in the same update); '
        'pending updates are kept for the next commit',
        mover.value,
      );
      return false;
    }
    for (final entry in removals.entries) {
      for (final child in _children[entry.key] ?? const <int>[]) {
        if (!entry.value.contains(child)) _destroySubtree(child);
      }
      _children[entry.key] = entry.value;
    }
    return true;
  }

  void _collectSubtree(int id, Set<int> into) {
    if (!into.add(id)) return;
    for (final kid in _children[id] ?? const <int>[]) {
      _collectSubtree(kid, into);
    }
  }

  void _destroySubtree(int id) {
    final subtree = <int>{};
    _collectSubtree(id, subtree);
    for (final n in subtree) {
      _nodes.remove(n);
      _parentOf.remove(n);
      _children.remove(n);
    }
  }

  /// סידור העדכון כמו `CommitUpdates` (אב לפני ילד) ואז `Unserialize`.
  void _applyPendingUpdates() {
    final remaining = Map.of(_pending);
    final lists = <List<RecordedSemanticsNode>>[];
    while (remaining.isNotEmpty) {
      final first = remaining.keys.first;
      final list = <RecordedSemanticsNode>[];
      final onPath = <int>{};
      void visit(RecordedSemanticsNode node) {
        onPath.add(node.id);
        list.add(node);
        for (final child in node.childrenInTraversalOrder) {
          final pending = remaining[child];
          if (pending == null) continue;
          if (onPath.contains(child)) {
            _violation(
              'cycle through $child in pending updates: '
              'GetSubTreeList recurses without end',
              node,
              crash: true,
            );
            continue;
          }
          visit(pending);
          remaining.remove(child);
        }
        onPath.remove(node.id);
      }

      visit(remaining[first]!);
      remaining.remove(first);
      lists.add(list);
    }
    final ordered = [for (final l in lists.reversed) ...l];
    if (ordered.isEmpty) return;
    final rootCreated = _root == null;
    final rootId = rootCreated ? lists.last.first.id : _root!;

    // ComputePendingChanges: מאמת הכול לפני שמשנים את העץ.
    final exists = Set.of(_nodes);
    final needsInit = <int>{};
    final lastKnown = <int, List<int>>{};
    List<int> childrenOf(int id) =>
        lastKnown[id] ?? _children[id] ?? const <int>[];
    void markDestroyed(int id) {
      if (!exists.remove(id)) return;
      for (final kid in childrenOf(id)) {
        markDestroyed(kid);
      }
    }

    String? error;
    RecordedSemanticsNode? failed;
    for (final data in ordered) {
      final kids = data.childrenInTraversalOrder;
      if (!exists.contains(data.id)) {
        if (rootCreated && data.id == rootId) {
          exists.add(data.id);
          needsInit.add(data.id);
        } else {
          error =
              '${data.id} will not be in the tree and is not the new root '
              '(אף צומת בעדכון אינו מצהיר עליו כילד)';
        }
      }
      if (error == null && kids.toSet().length != kids.length) {
        error = 'Node ${data.id} has duplicate child id';
      }
      if (error == null && needsInit.remove(data.id)) {
        for (final child in kids) {
          if (!exists.add(child)) {
            error =
                'Node $child is already pending for creation, '
                'cannot be a new child of ${data.id}';
            break;
          }
          needsInit.add(child);
        }
      } else if (error == null) {
        final old = childrenOf(data.id);
        for (final child in kids) {
          if (old.contains(child)) continue;
          if (!exists.add(child)) {
            error =
                'Node $child is not marked for destruction, '
                'would be reparented to ${data.id}';
            break;
          }
          needsInit.add(child);
        }
        if (error == null) {
          for (final child in old) {
            if (!kids.contains(child)) markDestroyed(child);
          }
        }
      }
      if (error != null) {
        failed = data;
        break;
      }
      lastKnown[data.id] = kids;
    }
    if (error != null) {
      // ComputePendingChanges נכשל לפני שינוי; העץ של המנוע נשאר כפי שהיה.
      _violation(error, failed!);
      return;
    }

    // ההחלה: צמתים שנוצרו כילדים ולא קיבלו נתונים נשארים בעץ, ריקים.
    final newChildren = <int, List<int>>{};
    final newParents = <int, int>{};
    final newNodes = <int>{};
    void build(int id) {
      if (!newNodes.add(id)) return;
      final kids =
          lastKnown[id] ??
          (needsInit.contains(id) ? null : _children[id]) ??
          const <int>[];
      newChildren[id] = List.of(kids);
      for (final kid in kids) {
        newParents[kid] = id;
        build(kid);
      }
    }

    build(rootId);
    _root = rootId;
    _nodes
      ..clear()
      ..addAll(newNodes);
    _children
      ..clear()
      ..addAll(newChildren);
    _parentOf
      ..clear()
      ..addAll(newParents);
    if (needsInit.isNotEmpty) {
      final parentId = newParents[needsInit.first];
      _violation(
        'Nodes left pending by the update: ${needsInit.join(' ')} '
        '(הוצהרו כילדים חדשים אך אינם בעדכון)',
        ordered.firstWhere(
          (n) => n.id == parentId,
          orElse: () => ordered.first,
        ),
      );
    }
  }
}

/// ה-builder של המסגרת, עטוף: מתעד כל `updateNode` ומעביר הלאה כרגיל.
class _RecordingSemanticsUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingSemanticsUpdateBuilder(this._inner, this._recorder);

  final ui.SemanticsUpdateBuilder _inner;
  final SemanticsUpdateRecorder _recorder;
  final List<RecordedSemanticsNode> _nodes = [];

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required ui.Rect rect,
    required String identifier,
    required String label,
    required List<ui.StringAttribute> labelAttributes,
    required String value,
    required List<ui.StringAttribute> valueAttributes,
    required String increasedValue,
    required List<ui.StringAttribute> increasedValueAttributes,
    required String decreasedValue,
    required List<ui.StringAttribute> decreasedValueAttributes,
    required String hint,
    required List<ui.StringAttribute> hintAttributes,
    required String tooltip,
    required ui.TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String linkUrl = '',
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    _nodes.add(
      RecordedSemanticsNode(
        id: id,
        label: label,
        tooltip: tooltip,
        traversalParent: traversalParent,
        childrenInTraversalOrder: List<int>.from(childrenInTraversalOrder),
      ),
    );
    _inner.updateNode(
      id: id,
      flags: flags,
      actions: actions,
      maxValueLength: maxValueLength,
      currentValueLength: currentValueLength,
      textSelectionBase: textSelectionBase,
      textSelectionExtent: textSelectionExtent,
      platformViewId: platformViewId,
      scrollChildren: scrollChildren,
      scrollIndex: scrollIndex,
      traversalParent: traversalParent,
      scrollPosition: scrollPosition,
      scrollExtentMax: scrollExtentMax,
      scrollExtentMin: scrollExtentMin,
      rect: rect,
      identifier: identifier,
      label: label,
      labelAttributes: labelAttributes,
      value: value,
      valueAttributes: valueAttributes,
      increasedValue: increasedValue,
      increasedValueAttributes: increasedValueAttributes,
      decreasedValue: decreasedValue,
      decreasedValueAttributes: decreasedValueAttributes,
      hint: hint,
      hintAttributes: hintAttributes,
      tooltip: tooltip,
      textDirection: textDirection,
      transform: transform,
      hitTestTransform: hitTestTransform,
      childrenInTraversalOrder: childrenInTraversalOrder,
      childrenInHitTestOrder: childrenInHitTestOrder,
      additionalActions: additionalActions,
      headingLevel: headingLevel,
      linkUrl: linkUrl,
      role: role,
      controlsNodes: controlsNodes,
      validationResult: validationResult,
      hitTestBehavior: hitTestBehavior,
      inputType: inputType,
      locale: locale,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _inner.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    _recorder.apply(List.of(_nodes));
    _nodes.clear();
    return _inner.build();
  }
}

/// binding לבדיקות שמקליט את עדכוני הסמנטיקה דרך [recorder].
///
/// חייב להיווצר לפני `testWidgets` הראשון בקובץ (הבינדינג נקבע פעם אחת
/// לאיזולט): `SemanticsRecordingBinding.ensure();` בתחילת `main`.
///
/// מודל אחד לכל התהליך: עדכונים של כמה views נכנסים לאותו עץ, ולכן בבדיקה
/// עם יותר מ-view אחד יתקבלו הפרות שאינן אמיתיות.
class SemanticsRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  SemanticsRecordingBinding._();

  /// המקליט המשותף לכל הבדיקות בקובץ.
  static final SemanticsUpdateRecorder recorder = SemanticsUpdateRecorder();

  static SemanticsRecordingBinding? _instance;

  /// יוצר את ה-binding אם עוד לא נוצר, ומחזיר אותו.
  static SemanticsRecordingBinding ensure() =>
      _instance ??= SemanticsRecordingBinding._();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingSemanticsUpdateBuilder(
        super.createSemanticsUpdateBuilder(),
        recorder,
      );
}

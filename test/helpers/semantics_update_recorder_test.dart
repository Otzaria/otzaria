import 'package:flutter_test/flutter_test.dart';

import 'semantics_update_recorder.dart';

RecordedSemanticsNode _node(int id, [List<int> children = const []]) =>
    RecordedSemanticsNode(
      id: id,
      label: '',
      tooltip: '',
      traversalParent: -1,
      childrenInTraversalOrder: children,
    );

/// 0 → 1 → 2 → 3 → 4
SemanticsUpdateRecorder _chain() => SemanticsUpdateRecorder()
  ..apply([
    _node(0, [1]),
    _node(1, [2]),
    _node(2, [3]),
    _node(3, [4]),
    _node(4),
  ]);

void main() {
  test('צומת שעובר אב יחד עם תת-העץ שלו — המנוע מקבל את העדכון', () {
    final recorder = _chain();
    recorder.apply([
      _node(1, [5]),
      _node(5, [2]),
      _node(2, [3]),
      _node(3, [4]),
      _node(4),
    ]);
    expect(recorder.violations, isEmpty);
  });

  test(
    'מעבר אב מקונן נדחה בשלב הראשון, והעדכונים הממתינים מצטברים עד '
    'erase(end()) (issue #3336)',
    () {
      final recorder = _chain();
      // 2 עובר מ-1 ל-10, ובאותו עדכון 4 עובר מ-3 (שבתוך 2) ל-11 — כמו
      // בפתיחת ספר עם צורת הדף כשהנגישות פעילה.
      recorder.apply([
        _node(1, [10]),
        _node(10, [2]),
        _node(2, [11]),
        _node(11, [4]),
      ]);
      expect(recorder.violations, hasLength(1));
      expect(
        recorder.violations.single.message,
        contains('3 will not be in the tree'),
      );
      expect(recorder.violations.single.isCrash, isFalse);

      // 11 הישן עדיין ממתין ורושם את 4; צומת חדש רושם אותו שוב.
      recorder.apply([
        _node(0, [1, 12]),
        _node(12, [4]),
      ]);
      expect(recorder.violations.where((v) => v.isCrash), isNotEmpty);
    },
  );

  test('ילד שעובר אב ורשום פעמיים באותה רשימה — erase(end())', () {
    final recorder = _chain();
    recorder.apply([
      _node(1, [2, 6]),
      _node(6, [4, 4]),
      _node(3),
    ]);
    expect(recorder.violations.where((v) => v.isCrash), isNotEmpty);
  });

  test('השורש שנרשם כילד של צומת אחר — child->parent() ריק', () {
    final recorder = _chain();
    recorder.apply([
      _node(4, [0]),
    ]);
    expect(recorder.violations.where((v) => v.isCrash), isNotEmpty);
  });
}

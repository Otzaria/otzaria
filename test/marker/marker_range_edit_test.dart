import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/services/marker_range_edit.dart';

import 'marker_test_helpers.dart';

void main() {
  const source = 'בראשית ברא אלהים את השמים ואת הארץ';

  MarkerRangeEdit editOf(String phrase) => MarkerRangeEdit(
    mark: highlightFor('a', [segmentFor(0, source, phrase)]),
    firstSource: source,
    lastSource: source,
  );

  String marked(MarkerRangeEdit edit) =>
      MarkerRangeEdit.textOf(edit.buildSegments()!);

  test('adds and removes whole words at both edges', () {
    final edit = editOf('אלהים את');
    edit.growStart();
    expect(marked(edit), 'ברא אלהים את');
    edit.growEnd();
    expect(marked(edit), 'ברא אלהים את השמים');
    edit
      ..shrinkStart()
      ..shrinkEnd();
    expect(marked(edit), 'אלהים את');
    expect(edit.changed, isFalse);
  });

  test('a partly marked word grows to the whole word first', () {
    final edit = editOf('הים את');
    expect(edit.canGrowStart, isTrue);
    edit.growStart();
    expect(marked(edit), 'אלהים את');
  });

  test('never shrinks to nothing and stops at the paragraph edges', () {
    final edit = editOf('בראשית');
    expect(edit.canShrinkStart, isFalse);
    expect(edit.canShrinkEnd, isFalse);
    expect(edit.canGrowStart, isFalse);
    final last = editOf('הארץ');
    expect(last.canGrowEnd, isFalse);
  });

  test('the slider selects a span of words', () {
    final edit = editOf('את');
    expect(edit.wordSpan, (first: 3, last: 3));
    edit.setWordSpan(1, 4);
    expect(marked(edit), 'ברא אלהים את השמים');
  });

  test('a mark across paragraphs moves only its outer edges', () {
    const second = 'ויאמר אלהים יהי אור';
    final edit = MarkerRangeEdit(
      mark: highlightFor('a', [
        segmentFor(0, source, 'ואת הארץ'),
        segmentFor(1, second, 'ויאמר'),
      ]),
      firstSource: source,
      lastSource: second,
    );
    edit
      ..growStart()
      ..growEnd();
    final segments = edit.buildSegments()!;
    expect(segments.first.range.exactText, 'השמים ואת הארץ');
    expect(segments.last.range.exactText, 'ויאמר אלהים');
    expect(edit.canShrinkEnd, isTrue);
    edit.shrinkEnd();
    expect(edit.canShrinkEnd, isFalse);
  });

  test('reset returns to the saved edges, and the edge words follow', () {
    final edit = editOf('את');
    expect(edit.edgeWord(start: true), (start: 17, end: 19));
    edit
      ..growStart()
      ..growEnd();
    expect(marked(edit), 'אלהים את השמים');
    expect(edit.edgeWord(start: true), (start: 11, end: 16));
    expect(edit.edgeWord(start: false), (start: 20, end: 25));
    edit.reset();
    expect(edit.changed, isFalse);
    expect(marked(edit), 'את');
  });
}

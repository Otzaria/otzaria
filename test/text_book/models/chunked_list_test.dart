import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/models/chunked_list.dart';

void main() {
  test('sparse logical length preserves missing and boundary values', () {
    final empty = ChunkedList<String>.filled(1000000, '');
    final edit = empty.edit();
    edit.setRangeValues(255, ['אָ', 'בּ', '', 'ד']);
    final loaded = edit.build();

    expect(empty[255], '');
    expect(loaded.length, 1000000);
    expect(loaded.sublist(254, 260), ['', 'אָ', 'בּ', '', 'ד', '']);
    expect(loaded[999999], '');
    expect(() => loaded[-1], throwsRangeError);
    expect(() => loaded[1000000], throwsRangeError);
  });

  test(
    'published snapshots reject changes and editors cannot mutate after build',
    () {
      final original = ChunkedList<String>.from(['a', 'b'], defaultValue: '');
      final editor = original.edit()..[1] = 'c';
      final updated = editor.build();

      expect(original.toList(), ['a', 'b']);
      expect(updated.toList(), ['a', 'c']);
      expect(() => updated[0] = 'x', throwsUnsupportedError);
      expect(() => updated.length = 4, throwsUnsupportedError);
      expect(() => editor[0] = 'x', throwsStateError);
      expect(() => editor.length = 4, throwsStateError);
      expect(() => editor.build(), throwsStateError);
      expect(updated.toList(), ['a', 'c']);
    },
  );

  test(
    'unchanged edits preserve snapshot identity and flags represent blank lines',
    () {
      final text = ChunkedList<String>.filled(1000, '');
      final same = text.edit()..setRangeValues(400, ['', '']);
      expect(same.changed, isFalse);
      expect(identical(same.build(), text), isTrue);
      final flags = ChunkedList<bool>.filled(1000, false);
      final loadedFlags = (flags.edit()..setRangeValues(400, [true, true]))
          .build();
      expect(text[400], '');
      expect(loadedFlags[400], isTrue);
      expect(loadedFlags[399], isFalse);
      expect(
        identical(ChunkedList<String>.from(text, defaultValue: ''), text),
        isTrue,
      );
    },
  );

  test('shrink then grow does not restore discarded values', () {
    final original = ChunkedList<int>.from(
      List.generate(700, (i) => i + 1),
      defaultValue: 0,
    );
    final editor = original.edit()..length = 258;
    editor.length = 700;
    final updated = editor.build();
    expect(updated.sublist(255, 261), [256, 257, 258, 0, 0, 0]);
    expect(updated[699], 0);
    expect(original[699], 700);
  });

  test(
    'retain clears full and partial chunks without changing global indices',
    () {
      final original = ChunkedList<int>.from(
        List.generate(800, (i) => i + 1),
        defaultValue: 0,
      );
      final retained = original.retainRange(255, 513);
      expect(retained.length, 800);
      expect(retained[254], 0);
      expect(retained[255], 256);
      expect(retained[512], 513);
      expect(retained[513], 0);
      expect(original[799], 800);
      expect(
        retained.retainRange(200, 200).every((value) => value == 0),
        isTrue,
      );
    },
  );

  test('nullable values are distinct from a nonnull default', () {
    final list = ChunkedList<String?>.from([
      'default',
      null,
      'text',
    ], defaultValue: 'default');
    expect(list[1], isNull);
    expect(list.toList(), ['default', null, 'text']);
    final changed = (list.edit()..[2] = null).build();
    expect(changed[2], isNull);
  });

  test('random batches, retention and length changes match a normal list', () {
    final random = Random(7613);
    var snapshot = ChunkedList<int>.filled(1024, 0);
    var reference = List<int>.filled(1024, 0, growable: true);
    for (var run = 0; run < 150; run++) {
      final old = snapshot;
      final oldValues = reference.toList();
      final editor = snapshot.edit();
      final targetLength = 512 + random.nextInt(1024);
      if (targetLength < reference.length) {
        reference.length = targetLength;
      } else {
        reference.addAll(List.filled(targetLength - reference.length, 0));
      }
      editor.length = targetLength;
      for (var operation = 0; operation < 20; operation++) {
        final index = random.nextInt(targetLength);
        final value = random.nextInt(10);
        editor[index] = value;
        reference[index] = value;
      }
      if (run % 4 == 0) {
        final start = random.nextInt(targetLength);
        final end = start + random.nextInt(targetLength - start + 1);
        editor.retainRange(start, end);
        reference.fillRange(0, start, 0);
        reference.fillRange(end, targetLength, 0);
      }
      snapshot = editor.build();
      expect(snapshot.toList(), reference);
      expect(old.toList(), oldValues);
    }
  });
  test('non-default traversal preserves logical order and partial chunks', () {
    final edit = ChunkedList<String>.filled(777, '').edit();
    edit[776] = 'סוף';
    edit[512] = 'שלישי';
    edit[3] = 'אָבְגּ';
    edit[255] = 'שני';
    edit[256] = '';
    final result = edit.build();
    expect(result.nonDefaultValues, ['אָבְגּ', 'שני', 'שלישי', 'סוף']);
    expect(result.retainRange(4, 777).nonDefaultValues, [
      'שני',
      'שלישי',
      'סוף',
    ]);
    final nullable = ChunkedList<String?>.filled(257, 'default').edit();
    nullable[256] = null;
    nullable[0] = '';
    expect(nullable.build().nonDefaultValues, ['', null]);
  });

  test('bulk writes preserve chunks, no-op identity and defaults', () {
    final original = ChunkedList<int>.filled(777, 0);
    final editor = original.edit();
    editor.setRange(250, 520, List.generate(280, (index) => index), 10);
    editor.fillRange(256, 512, 0);
    editor.fillRange(768, 777, 7);
    final result = editor.build();
    expect(result.sublist(250, 257), [10, 11, 12, 13, 14, 15, 0]);
    expect(result.sublist(511, 521), [
      0,
      272,
      273,
      274,
      275,
      276,
      277,
      278,
      279,
      0,
    ]);
    expect(result.sublist(767, 777), [0, 7, 7, 7, 7, 7, 7, 7, 7, 7]);
    expect(original.nonDefaultValues, isEmpty);
    final same = result.edit();
    same.setRange(250, 256, [10, 11, 12, 13, 14, 15]);
    same.fillRange(256, 512, 0);
    same.fillRange(768, 777, 7);
    expect(same.changed, isFalse);
    expect(identical(same.build(), result), isTrue);
    final cleared = result.edit()..fillRange(0, 777, 0);
    expect(cleared.build().nonDefaultValues, isEmpty);
    expect(result[776], 7);
  });

  test('bulk input validation does not change the editor', () {
    final original = ChunkedList<int>.filled(512, 0);
    final editor = original.edit();
    expect(() => editor.setRange(-1, 1, [1, 2]), throwsRangeError);
    expect(() => editor.setRange(0, 513, [1]), throwsRangeError);
    expect(() => editor.setRange(2, 1, [1]), throwsRangeError);
    expect(() => editor.setRange(0, 1, [1], -1), throwsRangeError);
    expect(() => editor.setRange(0, 2, [1]), throwsStateError);
    expect(() => editor.setRange(0, 2, [1, 2], 1), throwsStateError);
    expect(() => editor.setRange(0, 3, Iterable.generate(2)), throwsStateError);
    expect(() => editor.fillRange(-1, 2, 0), throwsRangeError);
    expect(() => editor.fillRange(0, 513, 0), throwsRangeError);
    expect(() => editor.fillRange(0, 1), throwsA(isA<TypeError>()));
    editor.setRange(512, 512, const [], -1);
    editor.fillRange(512, 512, 0);
    expect(editor.changed, isFalse);
    expect(identical(editor.build(), original), isTrue);
    expect(() => editor.setRange(0, 1, [1]), throwsStateError);
    expect(() => editor.fillRange(0, 1, 1), throwsStateError);
    final nullable = ChunkedList<int?>.filled(257, 1).edit();
    nullable.fillRange(255, 257);
    expect(nullable.build().sublist(254), [1, null, null]);
  });

  test(
    'bulk self-copy and iterable views preserve overlapping source values',
    () {
      final values = List.generate(800, (index) => index + 1);
      final original = ChunkedList<int>.from(values, defaultValue: 0);
      final editor = original.edit();
      editor.setRange(230, 600, editor, 200);
      values.setRange(230, 600, values, 200);
      editor.setRange(190, 580, editor, 225);
      values.setRange(190, 580, values, 225);
      editor.setRange(250, 600, editor.getRange(220, 570));
      values.setRange(250, 600, values.getRange(220, 570).toList());
      expect(editor.build().toList(), values);
      expect(original[250], 251);
    },
  );
}

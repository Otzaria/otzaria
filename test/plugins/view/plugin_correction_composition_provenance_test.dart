import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';

void main() {
  TextEditingValue composing(String text, int start, int end) =>
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: end),
        composing: TextRange(start: start, end: end),
      );

  for (final source in ['אַבֹגָ', 'אַבֹאָ']) {
    test('הרכבה נעה משמרת את מקור התו שבין העריכות: $source', () {
      final drafts = <String>[];
      late PluginCorrectionController controller;
      controller = PluginCorrectionController(
        source,
        removeNikud: true,
        onEdit: () => drafts.add(controller.canonical),
      );
      addTearDown(controller.dispose);
      final visible = controller.text;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      controller.value = composing('ד${visible.substring(1)}', 0, 1);
      controller.value = composing('דבה', 2, 3);
      expect(controller.canonical, 'דבֹה');
      expect(drafts.last, 'דבֹה');
      controller.value = composing('${visible[0]}בה', 0, 1);
      expect(controller.canonical, 'אַבֹה');
      controller.value = composing(visible, 2, 3);
      expect(controller.canonical, source);
    });
  }

  test('הרחבה וביטול של הרכבה נעה מחזירים את המקור והטיוטה', () {
    const source = 'אַבֹגָ';
    final controller = PluginCorrectionController(source, removeNikud: true);
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('דבג', 0, 1);
    controller.value = composing('דבה', 2, 3);
    controller.value = composing('דבוז', 2, 4);
    expect(controller.canonical, 'דבֹוז');
    controller.value = composing('דבג', 2, 3);
    expect(controller.canonical, 'דבֹגָ');
    controller.value = const TextEditingValue(
      text: 'אבג',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(controller.canonical, source);
    expect(controller.undoValue.value.canonical, source);
  });

  test('ביטול וביצוע חוזר שומרים את המקור לאחר הרכבה נעה', () {
    const source = 'אַבֹגָ';
    final controller = PluginCorrectionController(source, removeNikud: true);
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    final original = controller.value;
    controller.value = composing('דבג', 0, 1);
    controller.value = composing('דבה', 2, 3);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    final edited = controller.value;
    expect(controller.undoValue.value.canonical, 'דבֹה');
    controller.value = original;
    expect(controller.canonical, source);
    controller.value = edited;
    expect(controller.canonical, 'דבֹה');
  });
  test('מחיקת אות חוזרת ותנועה משמרות את זהות השכנים', () {
    const source = 'בַבֹגָ';
    final controller = PluginCorrectionController(source, removeNikud: true);
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('בג', 0, 1);
    expect(controller.canonical, 'בֹגָ');
    controller.value = composing('בה', 1, 2);
    expect(controller.canonical, 'בֹה');
    controller.value = composing('בג', 1, 2);
    expect(controller.canonical, 'בֹגָ');
    controller.value = composing('בבג', 0, 1);
    expect(controller.canonical, source);
  });
  test('חיתוך והרחבה בתוך מקטע רב תווים משמרים שכנים ו-UTF-16', () {
    const source = 'אַבֹ😀גָ';
    final controller = PluginCorrectionController(source, removeNikud: true);
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('XYב😀ג', 0, 2);
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    controller.value = composing('XZב😀ג', 0, 2);
    expect(controller.canonical, 'XZבֹ😀גָ');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('Zב😀ג', 0, 1);
    expect(controller.canonical, 'Zבֹ😀גָ');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('אב😀ג', 0, 1);
    expect(controller.canonical, source);
  });

  test('עריכות אקראיות לפי בחירה שומרות כל תו וסימן שמחוץ לה', () {
    final random = Random(6111);
    for (var run = 0; run < 50; run++) {
      final atoms = ['בַ', 'בֹ', '😀', 'גָ', 'דּ'];
      final controller = PluginCorrectionController(
        atoms.join(),
        removeNikud: true,
      );
      try {
        for (var step = 0; step < 20; step++) {
          final from = random.nextInt(atoms.length + 1);
          final to = from + random.nextInt(atoms.length - from + 1);
          final inserted = List.generate(
            random.nextInt(3),
            (_) => String.fromCharCode(88 + random.nextInt(3)),
          );
          final start = atoms
              .take(from)
              .join()
              .replaceAll(
                RegExp(r'[\u05B0-\u05BC]'),
                '',
              )
              .length;
          final end = atoms
              .take(to)
              .join()
              .replaceAll(
                RegExp(r'[\u05B0-\u05BC]'),
                '',
              )
              .length;
          controller.selection = TextSelection(
            baseOffset: start,
            extentOffset: end,
          );
          atoms.replaceRange(from, to, inserted);
          final expected = atoms.join();
          final visible = expected.replaceAll(RegExp(r'[\u05B0-\u05BC]'), '');
          controller.value = composing(visible, 0, visible.length);
          expect(controller.canonical, expected, reason: 'run=$run step=$step');
        }
      } finally {
        controller.dispose();
      }
    }
  });

  test('הקלדה מחדש לאחר אישור הרכבה לא מחזירה סימנים מעריכה קודמת', () {
    final controller = PluginCorrectionController('אַבֹ', removeNikud: true);
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('גב', 0, 1);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('אב', 0, 1);
    expect(controller.canonical, 'אבֹ');
  });

  test('ביטול מחיקה חוזרת בעזרת composing החדש שומר את זהות המקור', () {
    const source = 'בַבֹגָ';
    final controller = PluginCorrectionController(source, removeNikud: true);
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    controller.value = composing('בג', 0, 1);
    controller.value = composing('בה', 1, 2);
    controller.value = composing('בבה', 0, 1);
    expect(controller.canonical, 'בַבֹה');
  });
}

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

import '../golden_harness.dart';

Widget _card(
  String text, {
  AppCardTone tone = AppCardTone.normal,
  bool selected = false,
  bool active = false,
}) => AppCard(
  onTap: () {},
  tone: tone,
  selected: selected,
  active: active,
  padding: const EdgeInsets.all(12),
  child: Text(text),
);

Widget _variants() => SizedBox(
  width: 360,
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        _card('בראשית'),
        _card('שמות (נבחר)', selected: true),
        _card('ויקרא (פעיל)', active: true),
        _card('במדבר (הדגשה)', tone: AppCardTone.primary),
        _card('דברים (שגיאה)', tone: AppCardTone.error),
        _card('יהושע (בתוך כרטיס)', tone: AppCardTone.inset),
      ],
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('AppCard: גוונים ומצבים, ${brightness.name}', (tester) async {
      await pumpGolden(tester, _variants(), brightness: brightness);
      await expectGolden('app_card_variants.${brightness.name}');
    });
  }
}

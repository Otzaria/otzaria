import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';

void main() {
  final metrics = AppMenuMetrics.create(compactMenus: false);
  final entries = [
    const AppMenuEntry<int>(
      value: 1,
      label: 'תווית ארוכה מאוד שרוחבה קובע את רוחב כל התפריט בלי חיתוך',
    ),
    const AppMenuEntry<int>(value: 2, label: 'קצר'),
  ];

  test('הגדלת טקסט מרחיבה את התפריט כך שהתווית הארוכה נכנסת', () {
    final plain = calculateAppMenuPreferredWidth(metrics, entries);
    final scaled = calculateAppMenuPreferredWidth(
      metrics,
      entries,
      textScaler: const TextScaler.linear(1.5),
    );
    final doubled = calculateAppMenuPreferredWidth(
      metrics,
      entries,
      textScaler: const TextScaler.linear(2.0),
    );
    expect(plain, greaterThan(metrics.menuMinWidth), reason: 'התווית מכתיבה');
    expect(scaled, greaterThan(plain * 1.3));
    expect(doubled, greaterThan(scaled));
  });

  test('אותה מדידה אסינכרונית עם אותה הגדלה', () async {
    const scaler = TextScaler.linear(1.5);
    expect(
      await calculateAppMenuPreferredWidthAsync(
        metrics,
        entries,
        textScaler: scaler,
      ),
      calculateAppMenuPreferredWidth(metrics, entries, textScaler: scaler),
    );
  });

  test('התקרה גוברת גם בהגדלה', () {
    expect(
      calculateAppMenuPreferredWidth(
        metrics,
        entries,
        maxWidth: 200,
        textScaler: const TextScaler.linear(2.0),
      ),
      200,
    );
  });
}

import 'package:flutter/material.dart';

Widget pulse(Widget child) => AnimatedOpacity(
  opacity: 1,
  // ui-lint: allow UIL-023 — הבהוב התקדמות שמעביר מידע, נשאר גם בהפחתת תנועה
  duration: const Duration(milliseconds: 900),
  child: child,
);

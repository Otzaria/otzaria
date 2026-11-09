import 'package:flutter/material.dart';

Widget plugin(VoidCallback f) {
  // ui-lint: allow UIL-002 — כפתור שהמראה שלו נקבע במניפסט של התוסף
  return TextButton(onPressed: f, child: const Text('הפעל'));
}

import 'package:flutter/material.dart';

// ui-lint: allow UIL-002 — כפתור שהמראה שלו נקבע במניפסט של התוסף
Widget plugin(VoidCallback f) => TextButton(onPressed: f, child: const Text('הפעל'));

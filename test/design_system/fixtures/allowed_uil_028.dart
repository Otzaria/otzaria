import 'package:flutter/material.dart';

Future<void> crash(BuildContext context) =>
    // ui-lint: allow UIL-028 — דיאלוג הקריסה נפתח על Navigator חיצוני, לפני האפליקציה
    showDialog<void>(context: context, builder: (_) => const SizedBox());

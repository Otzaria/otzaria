import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;

Widget text(VoidCallback f) =>
    TextButton /* LINT */ (onPressed: f, child: const Text('ביטול'));
Widget constText() =>
    const TextButton /* LINT */ (onPressed: null, child: Text('ביטול'));
Widget filled(VoidCallback f) =>
    FilledButton /* LINT */ (onPressed: f, child: const Text('שמור'));
Widget tonal(VoidCallback f) =>
    FilledButton.tonal /* LINT */ (onPressed: f, child: const Text('שמור'));
Widget outlined(VoidCallback f) =>
    OutlinedButton /* LINT */ (onPressed: f, child: const Text('עוד'));
Widget elevated(VoidCallback f) =>
    ElevatedButton /* LINT */ (onPressed: f, child: const Text('אישור'));
Widget withIcon(VoidCallback f) => TextButton.icon /* LINT */ (
  onPressed: f,
  icon: const Icon(null),
  label: const Text('הוסף'),
);
Widget prefixed(VoidCallback f) =>
    m.TextButton /* LINT */ (onPressed: f, child: const Text('ביטול'));

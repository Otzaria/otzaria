import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;

Widget text(VoidCallback f) => TextButton(onPressed: f, child: const Text('ביטול')); // LINT
Widget constText() => const TextButton(onPressed: null, child: Text('ביטול')); // LINT
Widget filled(VoidCallback f) => FilledButton(onPressed: f, child: const Text('שמור')); // LINT
Widget tonal(VoidCallback f) => FilledButton.tonal(onPressed: f, child: const Text('שמור')); // LINT
Widget outlined(VoidCallback f) => OutlinedButton(onPressed: f, child: const Text('עוד')); // LINT
Widget elevated(VoidCallback f) => ElevatedButton(onPressed: f, child: const Text('אישור')); // LINT
Widget withIcon(VoidCallback f) => TextButton.icon( // LINT
  onPressed: f,
  icon: const Icon(null),
  label: const Text('הוסף'),
);
Widget prefixed(VoidCallback f) => m.TextButton(onPressed: f, child: const Text('ביטול')); // LINT

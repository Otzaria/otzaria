import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;

Widget plain(VoidCallback f) =>
    IconButton(icon: const Icon(Icons.close), onPressed: f); // LINT
Widget filled(VoidCallback f) =>
    IconButton.filled(icon: const Icon(Icons.add), onPressed: f); // LINT
Widget tonal() =>
    const IconButton.filledTonal(icon: SizedBox(), onPressed: null); // LINT
Widget prefixed(VoidCallback f) =>
    m.IconButton(icon: const Icon(Icons.close), onPressed: f); // LINT

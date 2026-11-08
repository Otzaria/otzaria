import 'package:flutter/material.dart';

Widget tile() => const ListTile(hoverColor: Colors.transparent); // LINT
Widget ink(VoidCallback onTap) =>
    InkWell(onTap: onTap, splashColor: Colors.red); // LINT
ButtonStyle style(Color c) =>
    ButtonStyle(overlayColor: WidgetStatePropertyAll(c)); // LINT
Widget either(VoidCallback onTap, bool b, Color c) =>
    InkWell(onTap: onTap, hoverColor: b ? c : null); // LINT
Widget hovered(VoidCallback onTap, Color c) =>
    ListTile(onTap: onTap, trailing: const Icon(null), hoverColor: c); // LINT

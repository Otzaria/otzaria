import 'package:flutter/material.dart';

Widget a() => const Text('שלום', textAlign: TextAlign.right); // LINT
Widget b() => const Text('x', textAlign: TextAlign.left); // LINT
const TextAlign c = TextAlign.right; // LINT
TextAlign d(bool wide) => wide ? TextAlign.left : TextAlign.center; // LINT

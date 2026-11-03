import 'package:flutter/material.dart';

Widget a(Widget child) => Card(child: child); // LINT
Widget b() => const Card(child: SizedBox()); // LINT
Widget c(Widget child) => Card.filled(child: child); // LINT
Widget d() => const Card.outlined(child: SizedBox()); // LINT

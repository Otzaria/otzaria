import 'package:flutter/material.dart';

void show(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(bar(text)); // LINT
void hide(BuildContext context) =>
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar(); // LINT
Widget host(Widget child) => ScaffoldMessenger(child: child); // LINT
Widget constHost() => const ScaffoldMessenger(child: SizedBox()); // LINT
SnackBar bar(String text) => SnackBar(content: Text(text)); // LINT
SnackBar constBar() => const SnackBar(content: SizedBox()); // LINT

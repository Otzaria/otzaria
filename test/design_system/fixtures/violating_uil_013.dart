import 'package:flutter/material.dart';

Widget a() => const CircularProgressIndicator(); // LINT
Widget b(double v) => CircularProgressIndicator(value: v); // LINT
Widget c() => const CircularProgressIndicator.adaptive(); // LINT
Widget d() =>
    const Center(child: CircularProgressIndicator(strokeWidth: 2)); // LINT

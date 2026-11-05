import 'package:flutter/material.dart';

Widget card() => const Material(elevation: 2); // LINT
Widget menu(MenuThemeData menuTheme) =>
    Material(elevation: menuTheme.style?.elevation?.resolve({}) ?? 3); // LINT
Widget raised(bool hovered) => Material(elevation: hovered ? 4.0 : 0); // LINT
const BoxDecoration shadowed = BoxDecoration(
  boxShadow: [BoxShadow(blurRadius: 8)], // LINT
);

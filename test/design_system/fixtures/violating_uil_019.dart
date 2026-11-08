import 'package:flutter/material.dart';

BorderRadius card() => BorderRadius.circular(12); // LINT
const BorderRadius all = BorderRadius.all(Radius.circular(6)); // LINT
BorderRadiusDirectional start() => BorderRadiusDirectional.circular(8); // LINT
const ShapeBorder pill = StadiumBorder(); // LINT
Widget dot(Widget child) =>
    Material(shape: const CircleBorder(), child: child); // LINT

import 'package:flutter/material.dart';

const EdgeInsets a = EdgeInsets.only(left: 8); // LINT
const EdgeInsets b = EdgeInsets.fromLTRB(16, 8, 4, 8); // LINT
const Alignment c = Alignment.centerRight; // LINT
Widget d(Widget child) => Positioned(left: 4, top: 0, child: child); // LINT
const Alignment e = Alignment(-1, 0); // LINT
const BorderRadius f = BorderRadius.only(topLeft: Radius.circular(8)); // LINT
const BorderRadius g = /* LINT */ BorderRadius.horizontal(
  right: Radius.circular(8),
);
const BorderRadius h = /* LINT */ BorderRadius.only(
  topLeft: Radius.circular(8),
  topRight: Radius.circular(8),
  bottomLeft: Radius.circular(8),
);

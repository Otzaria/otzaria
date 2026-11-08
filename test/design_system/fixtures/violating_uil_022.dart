import 'package:flutter/material.dart';

bool narrow(BoxConstraints constraints) => constraints.maxWidth < 520; // LINT
bool wide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 840; // LINT
bool reversed(Size size) => 600 > size.width; // LINT
bool local(BoxConstraints constraints) {
  final width = constraints.maxWidth;
  return width < 600; // LINT
}

bool screen(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return screenWidth >= 900; // LINT
}

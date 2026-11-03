import 'package:flutter/material.dart';

class AppTokens {
  static const double iconSM = 16;
}

const Widget a = Icon(IconData(0xe000), size: AppTokens.iconSM);
const Widget b = Icon(IconData(0xe000));
Widget c(double base) => Icon(const IconData(0xe000), size: base * 0.8);
const Widget box = SizedBox(width: 18, height: 18);
const Size size = Size(18, 18);

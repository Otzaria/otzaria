import 'package:flutter/material.dart';

Widget a() => const TextField(
  // ui-lint: allow UIL-040 — כתובת אינטרנט היא LTR תמיד (JX-09)
  textAlign: TextAlign.left,
);

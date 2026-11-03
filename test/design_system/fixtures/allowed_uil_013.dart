import 'package:flutter/material.dart';

// ui-lint: allow UIL-013 — התקדמות מדודה (value), ש־LoadingIndicator לא מציג
Widget progress(double v) => CircularProgressIndicator(value: v);

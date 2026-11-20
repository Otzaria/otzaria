import 'package:flutter/material.dart';

// ui-lint: allow UIL-039 — מתג מקטעים של Material בתוך הרכיב המשותף עצמו
Widget a() => SegmentedButton<int>(segments: const [], selected: const {});

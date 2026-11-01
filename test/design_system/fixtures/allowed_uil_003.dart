import 'package:flutter/material.dart';

Widget decorative(IconData icon) =>
    // ui-lint: allow UIL-003 — כפתור דקורטיבי מושבת, מוסתר מקורא המסך
    ExcludeSemantics(child: IconButton(onPressed: null, icon: Icon(icon)));

import 'package:flutter/material.dart';

Widget strip(ScrollController c, Widget child) =>
    // ui-lint: allow UIL-031 — פס אופקי; הכלל עוסק בצד של פס אנכי
    Scrollbar(controller: c, child: child);

import 'package:flutter/material.dart';

Widget drop(VoidCallback onTap) => InkWell(
  onTap: onTap,
  // ui-lint: allow UIL-007 — אזור שחרור בגרירה, ההדגשה מצוירת בנפרד
  hoverColor: Colors.transparent,
);

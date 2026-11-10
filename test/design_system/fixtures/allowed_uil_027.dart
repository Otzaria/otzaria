import 'package:flutter/material.dart';

// ui-lint: allow UIL-027 — צבע הנייר של תצוגה מקדימה, תוכן ולא כרום (JX-05)
Color paper(bool isDark) => isDark ? Colors.black : Colors.white;

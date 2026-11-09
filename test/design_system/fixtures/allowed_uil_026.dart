import 'package:flutter/material.dart';

// ui-lint: allow UIL-026 — טור הסת"ם בפריסה קבועה של עמוד ספר תורה (JX-10)
Widget column(Widget child) => MediaQuery.withNoTextScaling(child: child);

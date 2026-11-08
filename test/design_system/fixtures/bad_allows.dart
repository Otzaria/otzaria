import 'package:flutter/material.dart';

// ui-lint: allow UIL-004
Color noReason(BuildContext context) => Theme.of(context).primaryColor;

// ui-lint: allow UIL-004 — קצר
Color shortReason(BuildContext context) => Theme.of(context).primaryColor;

// ui-lint: allow all — נימוק ארוך מספיק לכל הכללים
Color everything(BuildContext context) => Theme.of(context).primaryColor;

// ui-lint: allow UIL-004, UIL-015 — נימוק ארוך מספיק לשני כללים
Color twoRules(BuildContext context) => Theme.of(context).primaryColor;

// ui-lint: allow UIL-004 — נימוק ארוך מספיק, אבל אין כאן חריגה
Color nothing(BuildContext context) => Theme.of(context).colorScheme.primary;

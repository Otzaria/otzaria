import 'package:flutter/material.dart';

// ui-lint: allow UIL-014 — תפריט ההקשר של שדה הטקסט, נבנה מעל SelectableRegion
Future<int?> open(BuildContext context) => showMenu<int>(
  context: context,
  position: RelativeRect.fill,
  items: const [],
);

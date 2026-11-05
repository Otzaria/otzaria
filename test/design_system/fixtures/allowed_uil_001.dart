import 'package:flutter/material.dart';

// ui-lint: allow UIL-001 — דיאלוג מערכת שמחקה את חלון ההדפסה של Windows
Widget printDialog(String body) => Dialog(child: Text(body));

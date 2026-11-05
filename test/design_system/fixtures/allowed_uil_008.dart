import 'package:flutter/material.dart';

// ui-lint: allow UIL-008 — מסך שגיאת האתחול, לפני ש־UiSnack מחובר לחלון
Widget host(Widget child) => ScaffoldMessenger(child: child);

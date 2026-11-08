import 'package:flutter/material.dart';

// ui-lint: allow UIL-016 — צבע המרקר שהמשתמש בחר, מעומעם לפי הגדרת השקיפות
Color marker(Color userColor, double a) => userColor.withValues(alpha: a);

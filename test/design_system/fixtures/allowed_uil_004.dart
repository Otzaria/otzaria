import 'package:flutter/material.dart';

Color legacy(BuildContext context) =>
    // ui-lint: allow UIL-004 — תוסף צד שלישי מצפה לצבע הזה בדיוק
    Theme.of(context).primaryColor;

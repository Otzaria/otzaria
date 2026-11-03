import 'package:flutter/material.dart';

Widget quote() => const Text(
  'וְצִדְקָתוֹ עֹמֶדֶת לָעַד',
  // ui-lint: allow UIL-010 — ציטוט תורני נשאר עברי גם כשההגדרות באנגלית
  textDirection: TextDirection.rtl,
);

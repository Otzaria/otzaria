import 'package:flutter/material.dart';

Widget plain(VoidCallback onPressed, IconData icon) =>
    IconButton(onPressed: onPressed, icon: Icon(icon), tooltip: 'סגור');

ButtonStyle style(Color color) => IconButton.styleFrom(foregroundColor: color);

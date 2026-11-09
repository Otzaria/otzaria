import 'package:flutter/material.dart';

Widget plain(VoidCallback onPressed, IconData icon) =>
    IconButton(onPressed: onPressed, icon: Icon(icon)); // LINT
Widget filled(VoidCallback onPressed, IconData icon) =>
    IconButton.filled(onPressed: onPressed, icon: Icon(icon)); // LINT

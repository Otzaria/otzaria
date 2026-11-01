import 'package:flutter/material.dart';

Widget alert(String title) => AlertDialog(title: Text(title)); // LINT
Widget constAlert() => const AlertDialog(title: Text('כותרת')); // LINT
Widget dialog(String body) => Dialog(child: Text(body)); // LINT
Widget fullscreen(String body) => Dialog.fullscreen(child: Text(body)); // LINT
Widget simple(String title) => SimpleDialog(title: Text(title)); // LINT

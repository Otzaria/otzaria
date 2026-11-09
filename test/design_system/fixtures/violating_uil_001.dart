import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;

Widget alert(String title) => AlertDialog(title: Text(title)); // LINT
Widget constAlert() => const AlertDialog(title: Text('כותרת')); // LINT
Widget dialog(String body) => Dialog(child: Text(body)); // LINT
Widget fullscreen(String body) => Dialog.fullscreen(child: Text(body)); // LINT
Widget simple(String title) => SimpleDialog(title: Text(title)); // LINT
Widget prefixed(String title) => m.AlertDialog(title: Text(title)); // LINT

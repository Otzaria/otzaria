import 'package:flutter/material.dart';
import 'package:otzaria/widgets/input_dialog.dart';

Future<String?> passwordDialog(BuildContext context) async {
  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return const InputDialog(
        title: 'Enter password',
        labelText: 'Password',
        keyboardType: TextInputType.visiblePassword,
        obscureText: true,
        confirmText: 'OK',
        cancelText: 'Cancel',
      );
    },
  );
}

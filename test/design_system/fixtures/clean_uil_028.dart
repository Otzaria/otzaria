import 'package:flutter/material.dart';

WidgetBuilder settingsDialogBuilder(
  BuildContext context,
  WidgetBuilder builder,
) => builder;

Future<T?> showDialogUntilTornDown<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async => null;

Future<void> scoped(BuildContext context) => showDialog<void>(
  context: context,
  builder: settingsDialogBuilder(context, (_) => const SizedBox()),
);

Future<void> tornDown(BuildContext context) => showDialogUntilTornDown<void>(
  context: context,
  builder: (_) => const SizedBox(),
);

class Messenger {
  Future<void> showDialog() async {}
}

Future<void> otherReceiver(Messenger messenger) => messenger.showDialog();

Future<void> scopedAdaptive(BuildContext context) => showAdaptiveDialog<void>(
  context: context,
  builder: settingsDialogBuilder(context, (_) => const SizedBox()),
);

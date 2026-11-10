import 'package:flutter/material.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

class AppFutureBuilder<T> extends StatelessWidget {
  final Future<T>? future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loadingWidget;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// ערך שכבר ידוע: מוצג מיד, בלי פריים טעינה עד שה-Future מדווח.
  final T? initialData;

  const AppFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.loadingWidget,
    this.errorBuilder,
    this.initialData,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      initialData: initialData,
      builder: (context, snapshot) {
        if (initialData == null &&
            (snapshot.connectionState == ConnectionState.waiting ||
                snapshot.connectionState == ConnectionState.none)) {
          return loadingWidget ?? const Center(child: LoadingIndicator());
        }

        if (snapshot.hasError) {
          if (errorBuilder != null) {
            return errorBuilder!(context, snapshot.error!);
          }
          return Center(
            child: Text(
              context.settingsText(
                'שגיאה: {error}',
                args: {'error': snapshot.error},
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        return builder(context, snapshot.data as T);
      },
    );
  }
}

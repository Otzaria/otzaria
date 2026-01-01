import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/loading_indicator.dart';

class TextBookStateBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, TextBookLoaded state) builder;
  final Widget? loadingWidget;
  final BlocBuilderCondition<TextBookState>? buildWhen;

  const TextBookStateBuilder({
    super.key,
    required this.builder,
    this.loadingWidget,
    this.buildWhen,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(
      buildWhen: buildWhen,
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return loadingWidget ?? const LoadingIndicator();
        }
        return builder(context, state);
      },
    );
  }
}

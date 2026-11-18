import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:flutter/material.dart';

/// Shows a spinner, an error with retry, or [builder] depending on [status].
class LoadStateView extends StatelessWidget {
  const LoadStateView({
    super.key,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.builder,
  });

  final LoadStatus status;
  final String? errorMessage;
  final VoidCallback onRetry;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case LoadStatus.initial:
      case LoadStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case LoadStatus.failure:
        return ErrorState(message: errorMessage ?? '', onRetry: onRetry);
      case LoadStatus.ready:
        return builder(context);
    }
  }
}

import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:flutter/material.dart';

/// Shows a floating message at the bottom of the screen.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: isError ? scheme.error : null,
        content: Text(
          message,
          style: TextStyle(color: isError ? scheme.onError : null),
        ),
      ),
    );
}

/// Asks the user to confirm an action; resolves to `true` when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = AppStrings.confirm,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A modal bottom sheet that lifts above the keyboard.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

/// Runs [action] and tells the user how it went.
///
/// Shows [successMessage] when it worked, or the error text when it failed.
/// Returns whether it worked.
Future<bool> runUiAction(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  try {
    await action();
    if (successMessage != null && context.mounted) {
      showAppSnackBar(context, successMessage);
    }
    return true;
  } on AppException catch (error) {
    if (context.mounted) showAppSnackBar(context, error.message, isError: true);
    return false;
  } catch (error, stackTrace) {
    debugPrint('Action failed: $error\n$stackTrace');
    if (context.mounted) {
      showAppSnackBar(context, AppStrings.unexpectedError, isError: true);
    }
    return false;
  }
}

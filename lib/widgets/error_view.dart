import 'package:flutter/material.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_messages.dart';

/// A reusable error view widget for displaying errors in the UI
class ErrorView extends StatelessWidget {
  final String message;
  final String? details;
  final VoidCallback? onRetry;
  final bool isCompact;

  const ErrorView({
    super.key,
    required this.message,
    this.details,
    this.onRetry,
    this.isCompact = false,
  });

  /// Create an ErrorView from an AppException
  factory ErrorView.fromException(
    AppException exception, {
    VoidCallback? onRetry,
    bool isCompact = false,
  }) {
    return ErrorView(
      message: ErrorMessages.getMessage(exception),
      details: exception.technicalDetails,
      onRetry: exception.isRetryable ? onRetry : null,
      isCompact: isCompact,
    );
  }

  /// Create an ErrorView from a generic error
  factory ErrorView.fromError(
    Object error, {
    VoidCallback? onRetry,
    bool isCompact = false,
  }) {
    if (error is AppException) {
      return ErrorView.fromException(error, onRetry: onRetry, isCompact: isCompact);
    }
    return ErrorView(
      message: 'Something went wrong',
      details: error.toString(),
      onRetry: onRetry,
      isCompact: isCompact,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompact(context);
    }
    return _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: onRetry,
              color: theme.colorScheme.onErrorContainer,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A widget that handles loading, error, and data states
class AsyncContentView<T> extends StatelessWidget {
  final bool isLoading;
  final Object? error;
  final T? data;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loadingWidget;
  final Widget? emptyWidget;

  const AsyncContentView({
    super.key,
    required this.isLoading,
    this.error,
    this.data,
    required this.builder,
    this.onRetry,
    this.loadingWidget,
    this.emptyWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return loadingWidget ?? const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return ErrorView.fromError(error!, onRetry: onRetry);
    }

    if (data == null) {
      return emptyWidget ?? const Center(child: Text('No data available'));
    }

    return builder(data as T);
  }
}

/// Extension to show error snackbars consistently
extension ErrorSnackBar on BuildContext {
  void showErrorSnackBar(Object error, {VoidCallback? onRetry}) {
    final message = error is AppException
        ? ErrorMessages.getMessage(error)
        : 'Something went wrong';

    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(this).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        action: onRetry != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: Theme.of(this).colorScheme.onError,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  void showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

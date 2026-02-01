import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:logging/logging.dart';

import '../models/error_model.dart';

/// Error boundary widget that catches and displays errors gracefully
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final String? fallbackMessage;
  final Widget? fallbackWidget;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallbackMessage,
    this.fallbackWidget,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  static final Logger _logger = Logger('ErrorBoundary');

  ShamorZachorError? _error;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    // Set up global error handler for Flutter errors
    FlutterError.onError = (FlutterErrorDetails details) {
      _logger.severe('Flutter error caught by ErrorBoundary', details.exception,
          details.stack);

      if (mounted) {
        setState(() {
          _hasError = true;
          _error = ShamorZachorError.fromException(
            details.exception,
            stackTrace: details.stack,
            customMessage: 'An unexpected error occurred',
          );
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError && _error != null) {
      return _buildErrorWidget(context, _error!);
    }

    // Wrap child in error catching
    return _ErrorCatcher(
      onError: (error, stackTrace) {
        _logger.severe('Error caught by ErrorBoundary', error, stackTrace);

        setState(() {
          _hasError = true;
          if (error is ShamorZachorError) {
            _error = error;
          } else {
            _error = ShamorZachorError.fromException(
              error,
              stackTrace: stackTrace,
              customMessage: 'An unexpected error occurred',
            );
          }
        });
      },
      child: widget.child,
    );
  }

  Widget _buildErrorWidget(BuildContext context, ShamorZachorError error) {
    if (widget.fallbackWidget != null) {
      return widget.fallbackWidget!;
    }

    // הסרנו את ה-Scaffold והחלפנו במבנה גמיש
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints
                  .maxHeight, // מבטיח שהתוכן יתפוס לפחות את כל הגובה הפנוי
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, // ממורכז אנכית
                crossAxisAlignment: CrossAxisAlignment.center, // ממורכז אופקית
                children: [
                  const Icon(
                    FluentIcons.error_circle_24_regular,
                    size: 64,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.fallbackMessage ?? error.userFriendlyMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  if (error.suggestedAction != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error.suggestedAction!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (error.isRecoverable)
                        ElevatedButton.icon(
                          icon: const Icon(FluentIcons.arrow_sync_24_regular),
                          onPressed: _retry,
                          label: const Text('נסה שוב'),
                        ),
                      if (error.isRecoverable) const SizedBox(width: 16),
                      OutlinedButton(
                        onPressed: _reset,
                        child: const Text('איפוס'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (kDebugMode && error.details != null) ...[
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: const Text('פרטים טכניים'),
                      children: [
                        // This Container with a fixed height is the key.
                        // It gives the inner SingleChildScrollView bounded constraints.
                        Container(
                          height: 150,
                          width: double.infinity,
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            'Type: ${error.type}\n\nMessage: ${error.message}\n\nDetails: ${error.details}\n\nStackTrace: ${error.stackTrace ?? 'N/A'}', // הוספנו את ה-StackTrace
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _error = null;
    });
  }

  void _reset() {
    setState(() {
      _hasError = false;
      _error = null;
    });

    // Navigate back to root or refresh the app
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }
}

/// Internal widget that catches errors in its child
class _ErrorCatcher extends StatefulWidget {
  final Widget child;
  final void Function(Object error, StackTrace stackTrace) onError;

  const _ErrorCatcher({
    required this.child,
    required this.onError,
  });

  @override
  State<_ErrorCatcher> createState() => _ErrorCatcherState();
}

class _ErrorCatcherState extends State<_ErrorCatcher> {
  @override
  Widget build(BuildContext context) {
    try {
      return widget.child;
    } catch (error, stackTrace) {
      widget.onError(error, stackTrace);
      return const SizedBox.shrink();
    }
  }
}

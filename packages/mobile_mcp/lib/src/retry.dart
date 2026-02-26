/// Auto-retry policy for dropped WebSocket connections.
///
/// When the OS suspends the Tool app and the WebSocket drops,
/// [McpRetryPolicy] re-triggers the wakeup deep link, waits for
/// reconnection, and retries the failed JSON-RPC call — all
/// transparently to the developer's `callTool` Future.
library;

import 'logger.dart';

/// Configuration for automatic retry of dropped connections.
///
/// Used internally by [McpHost] to transparently recover from
/// OS-induced WebSocket disconnections.
class McpRetryPolicy {
  /// Maximum number of retry attempts before giving up.
  final int maxRetries;

  /// Base delay between retry attempts (exponential backoff is applied).
  final Duration baseDelay;

  /// Maximum delay cap for exponential backoff.
  final Duration maxDelay;

  /// Timeout for waiting for the Tool to respond to a wakeup deep link.
  final Duration wakeupTimeout;

  final McpLogger _logger;

  McpRetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 5),
    this.wakeupTimeout = const Duration(seconds: 10),
    McpLogger? logger,
  }) : _logger = logger ?? McpLogger(tag: 'McpRetry');

  /// Calculates the delay for the given [attempt] (0-indexed) using
  /// exponential backoff with a cap.
  Duration delayForAttempt(int attempt) {
    final ms = baseDelay.inMilliseconds * (1 << attempt);
    final capped = ms.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  /// Executes [action] with automatic retry logic.
  ///
  /// If [action] throws, it is retried up to [maxRetries] times.
  /// Before each retry, [onRetry] is called to allow the caller
  /// to re-establish the connection (e.g., re-triggering the wakeup).
  ///
  /// Returns the result of [action] on success.
  /// Throws the last error if all retries are exhausted.
  Future<T> execute<T>({
    required Future<T> Function() action,
    required Future<void> Function(int attempt) onRetry,
    bool Function(Object error)? shouldRetry,
  }) async {
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          _logger.info('Retry attempt $attempt/$maxRetries');
          final delay = delayForAttempt(attempt - 1);
          _logger.debug('Waiting ${delay.inMilliseconds}ms before retry');
          await Future.delayed(delay);
          await onRetry(attempt);
        }
        return await action();
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;

        if (shouldRetry != null && !shouldRetry(e)) {
          _logger.error('Non-retryable error, giving up', e, stack);
          rethrow;
        }

        _logger.warning('Attempt ${attempt + 1}/${maxRetries + 1} failed: $e');
      }
    }

    _logger.error('All $maxRetries retries exhausted', lastError, lastStack);
    throw lastError!; // ignore: only_throw_errors
  }
}

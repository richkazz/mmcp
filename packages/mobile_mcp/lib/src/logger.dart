/// Configurable logging for the MCP package.
///
/// [McpLogger] supports four log levels: [McpLogLevel.none],
/// [McpLogLevel.error], [McpLogLevel.info], and [McpLogLevel.debug].
/// Developers can set the level during initialization to control verbosity.
library;

/// Log levels for [McpLogger], ordered by increasing verbosity.
enum McpLogLevel {
  /// No logging output.
  none,

  /// Only errors are logged.
  error,

  /// Errors and informational messages.
  info,

  /// Full debug output including raw JSON-RPC payloads.
  debug,
}

/// A configurable logger for MCP operations.
///
/// Set the [level] to control how much output is produced.
/// All output goes through [_output] which defaults to `print()`
/// but can be overridden for testing.
///
/// Example:
/// ```dart
/// final logger = McpLogger(level: McpLogLevel.debug, tag: 'McpHost');
/// logger.debug('Connecting to WebSocket on port 54321');
/// ```
class McpLogger {
  /// The current log level.
  final McpLogLevel level;

  /// A tag prepended to all log messages for filtering.
  final String tag;

  /// Output function, replaceable for testing.
  final void Function(String message) _output;

  /// Creates an [McpLogger] with the given [level] and optional [tag].
  McpLogger({
    this.level = McpLogLevel.info,
    this.tag = 'MCP',
    void Function(String message)? output,
  }) : _output = output ?? _defaultOutput;

  static void _defaultOutput(String message) {
    // ignore: avoid_print
    print(message);
  }

  /// Logs an error message. Always logged unless level is [McpLogLevel.none].
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (level.index >= McpLogLevel.error.index) {
      _output('[$tag] ERROR: $message');
      if (error != null) _output('[$tag] ERROR: $error');
      if (stackTrace != null) _output('[$tag] STACK: $stackTrace');
    }
  }

  /// Logs an informational message.
  void info(String message) {
    if (level.index >= McpLogLevel.info.index) {
      _output('[$tag] INFO: $message');
    }
  }

  /// Logs a debug message. Only logged at [McpLogLevel.debug].
  void debug(String message) {
    if (level.index >= McpLogLevel.debug.index) {
      _output('[$tag] DEBUG: $message');
    }
  }

  /// Logs a warning message. Logged at [McpLogLevel.info] and above.
  void warning(String message) {
    if (level.index >= McpLogLevel.info.index) {
      _output('[$tag] WARN: $message');
    }
  }
}

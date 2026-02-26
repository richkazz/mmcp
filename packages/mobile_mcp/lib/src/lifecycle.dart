/// Background task lifecycle management for MCP.
///
/// Provides platform channel hooks for brief keep-alive windows
/// during active WebSocket sessions:
/// - **iOS**: `beginBackgroundTask` / `endBackgroundTask`
/// - **Android**: temporary `Wakelock` tied to the session
///
/// This is NOT a persistent background service. It extends the
/// Dart VM's execution for ~30 seconds while apps are actively
/// communicating over the local WebSocket.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'logger.dart';

/// Manages brief background task extensions for active MCP sessions.
///
/// Call [acquireBackgroundLock] when the WebSocket server starts
/// and [releaseBackgroundLock] when the Host disconnects.
class McpLifecycle {
  static const MethodChannel _channel = MethodChannel('mobile_mcp/lifecycle');

  final McpLogger _logger;
  bool _hasBackgroundLock = false;

  McpLifecycle({McpLogger? logger})
    : _logger = logger ?? McpLogger(tag: 'McpLifecycle');

  /// Whether a background task lock is currently held.
  bool get hasBackgroundLock => _hasBackgroundLock;

  /// Requests a brief background execution extension from the OS.
  ///
  /// On iOS, this calls `beginBackgroundTask` which gives ~30 seconds.
  /// On Android, this acquires a partial `WakeLock`.
  ///
  /// Returns `true` if the lock was acquired successfully.
  Future<bool> acquireBackgroundLock() async {
    if (_hasBackgroundLock) {
      _logger.debug('Background lock already held');
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('acquireBackgroundLock');
      _hasBackgroundLock = result ?? false;
      if (_hasBackgroundLock) {
        _logger.info('Background lock acquired');
      } else {
        _logger.warning(
          'Failed to acquire background lock (platform returned false)',
        );
      }
      return _hasBackgroundLock;
    } on MissingPluginException {
      // Platform channel not implemented — running in debug/test or desktop.
      _logger.warning(
        'Background lock not available on this platform. '
        'WebSocket server may be killed when app is backgrounded.',
      );
      _hasBackgroundLock = true; // Assume success for non-mobile platforms
      return true;
    } catch (e, stack) {
      _logger.error('Failed to acquire background lock', e, stack);
      return false;
    }
  }

  /// Releases the background execution extension.
  ///
  /// On iOS, this calls `endBackgroundTask`.
  /// On Android, this releases the `WakeLock`.
  Future<void> releaseBackgroundLock() async {
    if (!_hasBackgroundLock) return;

    try {
      await _channel.invokeMethod<void>('releaseBackgroundLock');
      _logger.info('Background lock released');
    } on MissingPluginException {
      _logger.debug('Background lock release: platform channel not available');
    } catch (e, stack) {
      _logger.error('Failed to release background lock', e, stack);
    } finally {
      _hasBackgroundLock = false;
    }
  }

  /// Retrieves the calling app's package name (Android) or source app (iOS).
  ///
  /// Returns `null` if the information is unavailable.
  Future<String?> getCallingPackage() async {
    try {
      return await _channel.invokeMethod<String?>('getCallingPackage');
    } catch (e) {
      _logger.debug('Failed to get calling package: $e');
      return null;
    }
  }

  /// Checks if the current window is obscured by an overlay.
  ///
  /// Useful for preventing clickjacking on Android.
  Future<bool> isWindowObscured() async {
    try {
      return await _channel.invokeMethod<bool>('isWindowObscured') ?? false;
    } catch (e) {
      _logger.debug('Failed to check if window is obscured: $e');
      return false;
    }
  }
}

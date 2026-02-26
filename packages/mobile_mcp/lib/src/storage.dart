/// Pluggable storage interface for the MCP package.
///
/// Developers can implement [McpStorageProvider] to use secure storage
/// backends like `flutter_secure_storage` or a custom database.
/// The package ships with [SecureMcpStorage] as the default provider.
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'shared/models.dart';

/// Abstract interface for MCP persistence.
///
/// Implement this to provide custom storage backends.
///
/// Example:
/// ```dart
/// class SecureMcpStorage extends McpStorageProvider {
///   @override
///   Future<void> saveHost(McpRegistryEntry entry) async {
///     await secureStorage.write(key: entry.id, value: jsonEncode(entry.toJson()));
///   }
///   // ...
/// }
/// ```
abstract class McpStorageProvider {
  /// Saves or updates a host/tool registry entry.
  Future<void> saveEntry(McpRegistryEntry entry);

  /// Retrieves a registry entry by its [id].
  Future<McpRegistryEntry?> getEntry(String id);

  /// Retrieves all stored registry entries.
  Future<List<McpRegistryEntry>> getAllEntries();

  /// Removes a registry entry by its [id].
  Future<void> removeEntry(String id);

  /// Saves a session token for the given [appScheme].
  Future<void> saveSessionToken(String appScheme, String token);

  /// Retrieves the session token for the given [appScheme].
  Future<String?> getSessionToken(String appScheme);

  /// Removes the session token for the given [appScheme].
  Future<void> removeSessionToken(String appScheme);

  /// Clears all stored data.
  Future<void> clear();
}

/// Default in-memory + SharedPreferences storage implementation.
///
/// Uses an in-memory cache for fast access and persists data
/// to SharedPreferences for cross-session durability.
class DefaultMcpStorage extends McpStorageProvider {
  static const String _entryPrefix = 'mcp_entry_';
  static const String _tokenPrefix = 'mcp_token_';

  final Map<String, McpRegistryEntry> _cache = {};
  bool _initialized = false;

  /// Loads persisted entries into the in-memory cache.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_entryPrefix));
      for (final key in keys) {
        final jsonStr = prefs.getString(key);
        if (jsonStr != null) {
          final entry = McpRegistryEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(jsonStr) as Map),
          );
          _cache[entry.id] = entry;
        }
      }
    } catch (_) {
      // SharedPreferences may not be available in tests; rely on cache.
    }
  }

  @override
  Future<void> saveEntry(McpRegistryEntry entry) async {
    await _ensureInitialized();
    _cache[entry.id] = entry;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_entryPrefix${entry.id}',
        jsonEncode(entry.toJson()),
      );
    } catch (_) {
      // In-memory fallback.
    }
  }

  @override
  Future<McpRegistryEntry?> getEntry(String id) async {
    await _ensureInitialized();
    return _cache[id];
  }

  @override
  Future<List<McpRegistryEntry>> getAllEntries() async {
    await _ensureInitialized();
    return List.unmodifiable(_cache.values);
  }

  @override
  Future<void> removeEntry(String id) async {
    await _ensureInitialized();
    _cache.remove(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_entryPrefix$id');
    } catch (_) {}
  }

  @override
  Future<void> saveSessionToken(String appScheme, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_tokenPrefix$appScheme', token);
    } catch (_) {}
  }

  @override
  Future<String?> getSessionToken(String appScheme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_tokenPrefix$appScheme');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removeSessionToken(String appScheme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_tokenPrefix$appScheme');
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    _initialized = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
        (k) => k.startsWith(_entryPrefix) || k.startsWith(_tokenPrefix),
      );
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}

/// Secure storage implementation using `flutter_secure_storage`.
///
/// Persists sensitive tokens and registry entries using the platform's
/// secure storage (KeyChain on iOS, AES-256 on Android).
class SecureMcpStorage extends McpStorageProvider {
  static const String _entryPrefix = 'mcp_entry_';
  static const String _tokenPrefix = 'mcp_token_';

  final FlutterSecureStorage _storage;
  final Map<String, McpRegistryEntry> _cache = {};
  bool _initialized = false;

  SecureMcpStorage({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage(
         aOptions: AndroidOptions(encryptedSharedPreferences: true),
       );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_entryPrefix)) {
          final jsonStr = all[key];
          if (jsonStr != null) {
            final entry = McpRegistryEntry.fromJson(
              Map<String, dynamic>.from(jsonDecode(jsonStr) as Map),
            );
            _cache[entry.id] = entry;
          }
        }
      }
    } catch (_) {
      // Secure storage may not be available in some environments (e.g., tests)
    }
  }

  @override
  Future<void> saveEntry(McpRegistryEntry entry) async {
    await _ensureInitialized();
    _cache[entry.id] = entry;
    await _storage.write(
      key: '$_entryPrefix${entry.id}',
      value: jsonEncode(entry.toJson()),
    );
  }

  @override
  Future<McpRegistryEntry?> getEntry(String id) async {
    await _ensureInitialized();
    return _cache[id];
  }

  @override
  Future<List<McpRegistryEntry>> getAllEntries() async {
    await _ensureInitialized();
    return List.unmodifiable(_cache.values);
  }

  @override
  Future<void> removeEntry(String id) async {
    await _ensureInitialized();
    _cache.remove(id);
    await _storage.delete(key: '$_entryPrefix$id');
  }

  @override
  Future<void> saveSessionToken(String appScheme, String token) async {
    await _storage.write(key: '$_tokenPrefix$appScheme', value: token);
  }

  @override
  Future<String?> getSessionToken(String appScheme) async {
    return await _storage.read(key: '$_tokenPrefix$appScheme');
  }

  @override
  Future<void> removeSessionToken(String appScheme) async {
    await _storage.delete(key: '$_tokenPrefix$appScheme');
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    _initialized = false;
    await _storage.deleteAll();
  }
}

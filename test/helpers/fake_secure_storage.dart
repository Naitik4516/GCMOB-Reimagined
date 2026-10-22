import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory [FlutterSecureStorage] used by profile tests.
///
/// Suites that use it should still call
/// `SharedPreferences.setMockInitialValues({})` when the store touches prefs.
class FakeSecureStorage extends FlutterSecureStorage {
  FakeSecureStorage({
    this.throwOnWrite = false,
    this.throwOnRead = false,
    this.throwOnDelete = false,
  });

  final bool throwOnWrite;
  final bool throwOnRead;
  final bool throwOnDelete;
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnWrite) throw StateError('keyring unavailable');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnRead) throw StateError('keyring unavailable');
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnDelete) throw StateError('keyring unavailable');
    values.remove(key);
  }
}

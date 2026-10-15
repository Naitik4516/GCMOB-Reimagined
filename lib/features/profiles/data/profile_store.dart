import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dvr_profile.dart';

/// Persists profiles: non-secret fields in SharedPreferences (JSON list),
/// passwords in secure storage keyed by profile id.
class ProfileStore {
  static const _profilesKey = 'dvr_profiles_v1';
  static String _passKey(String id) => 'dvr_pass_$id';

  final FlutterSecureStorage _secure;

  ProfileStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  Future<List<DvrProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(DvrProfile.fromJson).toList();
  }

  Future<void> _saveProfiles(List<DvrProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> upsertProfile(DvrProfile profile, String password) async {
    final profiles = await loadProfiles();
    final i = profiles.indexWhere((p) => p.id == profile.id);
    if (i >= 0) {
      profiles[i] = profile;
    } else {
      profiles.add(profile);
    }
    await _saveProfiles(profiles);
    await _secure.write(key: _passKey(profile.id), value: password);
  }

  Future<void> deleteProfile(String id) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == id);
    await _saveProfiles(profiles);
    await _secure.delete(key: _passKey(id));
  }

  Future<String?> loadPassword(String id) => _secure.read(key: _passKey(id));

  static const _lastProfileKey = 'last_profile_id';
  static const _gridSizeKey = 'grid_size'; // 1, 4, 9
  static String _orderKey(String profileId) => 'ch_order_$profileId';

  Future<void> saveLastProfile(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastProfileKey, id);
  }

  Future<String?> loadLastProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastProfileKey);
  }

  Future<void> saveGridSize(int size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gridSizeKey, size);
  }

  Future<int> loadGridSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_gridSizeKey) ?? 4;
  }

  /// Loads the user-arranged channel order for [profileId], or `null` when
  /// nothing valid was stored. Must be exactly the set {1..[channelCount]}.
  Future<List<int>?> loadChannelOrder(
      String profileId, int channelCount) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderKey(profileId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toList();
      if (list.length != channelCount) return null;
      final sorted = [...list]..sort();
      for (var i = 0; i < channelCount; i++) {
        if (sorted[i] != i + 1) return null;
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveChannelOrder(String profileId, List<int> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderKey(profileId), jsonEncode(order));
  }
}

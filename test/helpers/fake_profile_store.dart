import 'package:gcmob_reimagined/features/profiles/data/profile_store.dart';
import 'package:gcmob_reimagined/features/profiles/models/dvr_profile.dart';

/// Configurable in-memory [ProfileStore] for cubit tests.
///
/// It never touches SharedPreferences or the platform keyring. Flip the
/// `throwOn…` flags to exercise failure paths between calls.
class FakeProfileStore extends ProfileStore {
  FakeProfileStore({List<DvrProfile> profiles = const []})
      : profiles = [...profiles];

  final List<DvrProfile> profiles;

  bool throwOnLoad = false;
  bool throwOnUpsert = false;
  bool throwOnDelete = false;

  int loadCalls = 0;
  int upsertCalls = 0;
  int deleteCalls = 0;

  final List<DvrProfile> upserted = [];
  final List<String> deleted = [];

  @override
  Future<List<DvrProfile>> loadProfiles() async {
    loadCalls++;
    if (throwOnLoad) throw StateError('load failed');
    return List.of(profiles);
  }

  @override
  Future<void> upsertProfile(DvrProfile profile, String password) async {
    upsertCalls++;
    if (throwOnUpsert) throw StateError('keyring unavailable');
    upserted.add(profile);
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
  }

  @override
  Future<void> deleteProfile(String id) async {
    deleteCalls++;
    if (throwOnDelete) throw StateError('delete failed');
    deleted.add(id);
    profiles.removeWhere((p) => p.id == id);
  }
}

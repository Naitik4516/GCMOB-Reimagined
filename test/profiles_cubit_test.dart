import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/features/profiles/bloc/profiles_cubit.dart';
import 'package:gcmob_reimagined/features/profiles/models/dvr_profile.dart';

import 'helpers/fake_profile_store.dart';

const _profile = DvrProfile(
  id: 'p1',
  name: 'Home',
  host: '192.168.1.10',
  rtspPort: 554,
  username: 'admin',
  channelCount: 4,
);

void main() {
  test('load publishes the stored profiles as a loaded state', () async {
    final cubit = ProfilesCubit(
      FakeProfileStore(profiles: const [_profile]),
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, ProfilesStatus.loaded);
    expect(cubit.state.profiles, const [_profile]);
    expect(cubit.state.error, isNull);
  });

  test('load reports storage failures as an error state', () async {
    final store = FakeProfileStore()..throwOnLoad = true;
    final cubit = ProfilesCubit(store);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, ProfilesStatus.error);
    expect(cubit.state.error, contains('load failed'));
  });

  test('retry after a load failure calls the store again', () async {
    final store = FakeProfileStore(profiles: const [_profile])
      ..throwOnLoad = true;
    final cubit = ProfilesCubit(store);
    addTearDown(cubit.close);

    await cubit.load();
    expect(cubit.state.status, ProfilesStatus.error);

    store.throwOnLoad = false;
    await cubit.load();

    expect(cubit.state.status, ProfilesStatus.loaded);
    expect(cubit.state.profiles, const [_profile]);
    expect(store.loadCalls, 2);
  });

  test('save propagates failures without blanking the loaded list', () async {
    final store = FakeProfileStore(profiles: const [_profile])
      ..throwOnUpsert = true;
    final cubit = ProfilesCubit(store);
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.status, ProfilesStatus.loaded);
    expect(cubit.state.profiles, const [_profile]);

    await expectLater(cubit.save(_profile, 'pw'), throwsStateError);

    expect(cubit.state.status, ProfilesStatus.loaded);
    expect(cubit.state.profiles, const [_profile]);
  });

  test('remove propagates failures and keeps the profile visible', () async {
    final store = FakeProfileStore(profiles: const [_profile])
      ..throwOnDelete = true;
    final cubit = ProfilesCubit(store);
    addTearDown(cubit.close);
    await cubit.load();

    await expectLater(cubit.remove('p1'), throwsStateError);

    expect(cubit.state.status, ProfilesStatus.loaded);
    expect(cubit.state.profiles, const [_profile]);
  });
}

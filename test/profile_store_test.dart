import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/features/profiles/data/profile_store.dart';
import 'package:gcmob_reimagined/features/profiles/models/dvr_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_secure_storage.dart';

DvrProfile profile({
  String id = 'p1',
  String name = 'Home',
  String host = '192.168.1.10',
  int port = 554,
  String user = 'admin',
  int channels = 4,
}) =>
    DvrProfile(
      id: id,
      name: name,
      host: host,
      rtspPort: port,
      username: user,
      channelCount: channels,
    );

void main() {
  late FakeSecureStorage secure;
  late ProfileStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = FakeSecureStorage();
    store = ProfileStore(secure: secure);
  });

  test('loadProfiles keeps valid records and skips corrupt ones', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dvr_profiles_v1',
      jsonEncode([
        profile(id: 'good1').toJson(),
        {
          'id': 'empty-name',
          'name': '',
          'host': '192.168.1.11',
          'rtspPort': 554,
          'username': 'admin',
          'channelCount': 4,
        },
        {
          'id': 'bad-port',
          'name': 'Bad port',
          'host': '192.168.1.12',
          'rtspPort': 70000,
          'username': 'admin',
          'channelCount': 4,
        },
        {
          'id': 'bad-count',
          'name': 'Bad count',
          'host': '192.168.1.13',
          'rtspPort': 554,
          'username': 'admin',
          'channelCount': 0,
        },
        {'id': 'missing-fields'},
        'not a map',
        profile(id: 'good2', channels: 8).toJson(),
      ]),
    );

    final loaded = await store.loadProfiles();
    expect(loaded.map((p) => p.id), ['good1', 'good2']);
    expect(loaded.last.channelCount, 8);
  });

  test('unreadable or non-list JSON yields an empty list', () async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('dvr_profiles_v1', 'not json');
    expect(await store.loadProfiles(), isEmpty);

    await prefs.setString('dvr_profiles_v1', '{"profiles": []}');
    expect(await store.loadProfiles(), isEmpty);
  });

  test('password is stored securely, not in the profile JSON', () async {
    await store.upsertProfile(profile(), 's3cret');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dvr_profiles_v1'), isNot(contains('s3cret')));
    expect(secure.values['dvr_pass_p1'], 's3cret');
    expect(await store.loadPassword('p1'), 's3cret');
  });

  test('editing with the stored password keeps it', () async {
    await store.upsertProfile(profile(), 'old-password');

    final kept = await store.loadPassword('p1');
    expect(kept, 'old-password');
    await store.upsertProfile(profile(name: 'Renamed'), kept!);

    expect(await store.loadPassword('p1'), 'old-password');
    expect((await store.loadProfiles()).single.name, 'Renamed');
  });

  test('channel count change clears the stored order', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dvr_profiles_v1',
      jsonEncode([profile(channels: 4).toJson()]),
    );
    await prefs.setString('ch_order_p1', jsonEncode([4, 3, 2, 1]));

    expect(await store.loadChannelOrder('p1', 4), [4, 3, 2, 1]);

    await store.upsertProfile(profile(channels: 8), 'pw');

    expect(prefs.getString('ch_order_p1'), isNull);
    expect(await store.loadChannelOrder('p1', 4), isNull);
  });

  test('deleteProfile clears password, order, and last-profile hint', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dvr_profiles_v1',
      jsonEncode([profile().toJson()]),
    );
    await prefs.setString('ch_order_p1', jsonEncode([2, 1, 3, 4]));
    await prefs.setString('last_profile_id', 'p1');

    await store.upsertProfile(profile(), 'pw');
    await store.deleteProfile('p1');

    expect(await store.loadProfiles(), isEmpty);
    expect(secure.values.containsKey('dvr_pass_p1'), isFalse);
    expect(await store.loadPassword('p1'), isNull);
    expect(prefs.getString('ch_order_p1'), isNull);
    expect(prefs.getString('last_profile_id'), isNull);
  });

  test('a failed password write does not save the profile', () async {
    final failing = ProfileStore(
      secure: FakeSecureStorage(throwOnWrite: true),
    );
    await expectLater(
      failing.upsertProfile(profile(), 'pw'),
      throwsStateError,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dvr_profiles_v1'), isNull);
  });

  test('keyring read and delete failures propagate', () async {
    final readFailing = ProfileStore(
      secure: FakeSecureStorage(throwOnRead: true),
    );
    await expectLater(readFailing.loadPassword('p1'), throwsStateError);

    final deleteFailing = ProfileStore(
      secure: FakeSecureStorage(throwOnDelete: true),
    );
    await deleteFailing.upsertProfile(profile(), 'pw');
    await expectLater(
      deleteFailing.deleteProfile('p1'),
      throwsStateError,
    );
    // The profile record is removed before the keyring delete is attempted,
    // so a failed cleanup cannot leave an unusable profile behind.
    expect(await deleteFailing.loadProfiles(), isEmpty);
  });
}

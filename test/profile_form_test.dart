import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/core/rtsp/rtsp_probe.dart';
import 'package:gcmob_reimagined/features/profiles/bloc/profiles_cubit.dart';
import 'package:gcmob_reimagined/features/profiles/models/dvr_profile.dart';
import 'package:gcmob_reimagined/features/profiles/ui/profile_form_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_profile_store.dart';

class _FakeProbe extends RtspProbe {
  RtspProbeResult result =
      const RtspProbeResult(RtspProbeStatus.ok, 'Connected.');

  int calls = 0;
  String? host;
  int? port;
  String? user;
  String? password;

  @override
  Future<RtspProbeResult> probe({
    required String host,
    required int port,
    required String user,
    required String password,
    int channelOneBased = 1,
  }) async {
    calls++;
    this.host = host;
    this.port = port;
    this.user = user;
    this.password = password;
    return result;
  }
}

class _Store extends FakeProfileStore {
  _Store({super.profiles});

  final Map<String, String> passwords = {};

  @override
  Future<String?> loadPassword(String id) async => passwords[id];
}

const _existing = DvrProfile(
  id: 'p1',
  name: 'Home DVR',
  host: '192.168.1.10',
  rtspPort: 554,
  username: 'admin',
  channelCount: 8,
);

Future<_Store> _pumpForm(
  WidgetTester tester, {
  required _FakeProbe probe,
  DvrProfile? existing,
}) async {
  // Tall surface so the lazily built ListView renders the Save button.
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = _Store(profiles: existing == null ? const [] : [existing]);
  if (existing != null) store.passwords[existing.id] = 'stored-secret';
  final cubit = ProfilesCubit(store);
  addTearDown(cubit.close);

  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        home: ProfileFormPage(
          existing: existing,
          probe: probe,
          store: store,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.text('Save');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<void> _fillNewProfile(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Profile Name'),
    'Front Gate',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'secret',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('invalid fields never reach the connection test', (tester) async {
    final probe = _FakeProbe();
    final store = await _pumpForm(tester, probe: probe);

    await _tapSave(tester);

    expect(probe.calls, 0);
    expect(store.upsertCalls, 0);
    expect(find.text('Required'), findsWidgets);
  });

  testWidgets('creating a profile tests the connection, then saves',
      (tester) async {
    final probe = _FakeProbe();
    final store = await _pumpForm(tester, probe: probe);
    await _fillNewProfile(tester);

    await _tapSave(tester);

    expect(probe.calls, 1);
    expect(probe.host, '192.168.1.240');
    expect(probe.port, 554);
    expect(probe.user, 'admin');
    expect(probe.password, 'secret');
    expect(store.upsertCalls, 1);
    expect(store.upserted.single.name, 'Front Gate');
  });

  testWidgets('a failed test blocks the save until the user opts in',
      (tester) async {
    final probe = _FakeProbe()
      ..result = const RtspProbeResult(
        RtspProbeStatus.authFailed,
        'The DVR rejected the username or password.',
      );
    final store = await _pumpForm(tester, probe: probe);
    await _fillNewProfile(tester);

    await _tapSave(tester);

    expect(probe.calls, 1);
    expect(find.text('Connection failed'), findsOneWidget);
    expect(store.upsertCalls, 0);

    await tester.tap(find.text('Fix it'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsNothing);
    expect(
      find.text('The DVR rejected the username or password.'),
      findsOneWidget,
    );
    expect(store.upsertCalls, 0);

    // A second save retests instead of trusting the stale failure.
    await _tapSave(tester);
    expect(probe.calls, 2);
    expect(find.text('Connection failed'), findsOneWidget);

    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();

    expect(store.upsertCalls, 1);
  });

  testWidgets('editing only the name skips the connection test',
      (tester) async {
    final probe = _FakeProbe();
    final store = await _pumpForm(
      tester,
      probe: probe,
      existing: _existing,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Profile Name'),
      'Renamed',
    );
    await _tapSave(tester);

    expect(probe.calls, 0);
    expect(store.upsertCalls, 1);
    expect(store.upserted.single.name, 'Renamed');
  });

  testWidgets('editing the host retests before saving', (tester) async {
    final probe = _FakeProbe();
    final store = await _pumpForm(
      tester,
      probe: probe,
      existing: _existing,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'DVR IP / Hostname'),
      '10.0.0.9',
    );
    await _tapSave(tester);

    expect(probe.calls, 1);
    expect(probe.host, '10.0.0.9');
    expect(store.upsertCalls, 1);
  });
}

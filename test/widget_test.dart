import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/app/app.dart';
import 'package:gcmob_reimagined/core/rtsp/mpv_errors.dart';
import 'package:gcmob_reimagined/core/rtsp/rtsp_concurrency.dart';
import 'package:gcmob_reimagined/core/rtsp/rtsp_url.dart';
import 'package:gcmob_reimagined/features/live/ui/camera_grid_widget.dart'
    show findTileIndex;
import 'package:gcmob_reimagined/features/profiles/bloc/profiles_cubit.dart';
import 'package:gcmob_reimagined/features/profiles/ui/profile_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Dahua RTSP URL builder uses 0-indexed channel + subtype flag', () {
    expect(
      buildDahuaRtsp(
        user: 'admin',
        pass: 'p@ss:word',
        host: '192.168.1.240',
        port: 554,
        channelOneBased: 1,
        highRes: false,
      ),
      'rtsp://admin:p%40ss%3Aword@192.168.1.240:554/cam/realmonitor?channel=0&subtype=1',
    );
    expect(
      buildDahuaRtsp(
        user: 'admin',
        pass: 'secret',
        host: '192.168.1.240',
        port: 554,
        channelOneBased: 4,
        highRes: true,
      ),
      'rtsp://admin:secret@192.168.1.240:554/cam/realmonitor?channel=3&subtype=0',
    );
    expect(
      buildDahuaRtsp(
        user: 'admin',
        pass: 'secret',
        host: '[fe80::1]',
        port: 554,
        channelOneBased: 1,
        highRes: false,
      ),
      'rtsp://admin:secret@[fe80::1]:554/cam/realmonitor?channel=0&subtype=1',
    );
  });

  test('normalizeRtspHost strips pasted URLs and brackets IPv6', () {
    expect(
      normalizeRtspHost('  rtsp://192.168.1.240/  '),
      '192.168.1.240',
    );
    expect(
      normalizeRtspHost('rtsp://dvr.local/cam/realmonitor'),
      'dvr.local',
    );
    expect(normalizeRtspHost('fe80::1'), '[fe80::1]');
    expect(normalizeRtspHost('[fe80::1]'), '[fe80::1]');
    expect(
      () => normalizeRtspHost('admin:secret@192.168.1.240'),
      throwsFormatException,
    );
    expect(
      () => normalizeRtspHost('192.168.1.240:554'),
      throwsFormatException,
    );
    expect(() => normalizeRtspHost(''), throwsFormatException);
  });

  test('redactRtspCredentials hides user:pass from displayed errors', () {
    expect(
      redactRtspCredentials(
          'rtsp://admin:secret@192.168.1.240:554/cam/realmonitor'),
      'rtsp://***:***@192.168.1.240:554/cam/realmonitor',
    );
    expect(
      redactRtspCredentials('admin:secret@192.168.1.240'),
      '***:***@192.168.1.240',
    );
    expect(redactRtspCredentials('Stream dropped'), 'Stream dropped');
  });

  test('isBenignLiveError filters seek notes only', () {
    expect(isBenignLiveError('Cannot seek in this stream'), isTrue);
    expect(isBenignLiveError('seek failed'), isTrue);
    // The standalone hint line carries no "cannot seek" wording.
    expect(
      isBenignLiveError("You can force it with '--force-seekable=yes'."),
      isTrue,
    );
    expect(isBenignLiveError('tcp: connection reset by peer'), isFalse);
    expect(isBenignLiveError(''), isFalse);
    expect(isBenignLiveError('Stream dropped'), isFalse);
  });

  test('findTileIndex maps keys to slots, unknown to null', () {
    const channels = [1, 3, 4, 2];
    expect(findTileIndex(const ValueKey('tile_abc_1_hd'), channels), 0);
    expect(findTileIndex(const ValueKey('tile_abc_3_sd'), channels), 1);
    expect(findTileIndex(const ValueKey('tile_abc_2_hd'), channels), 3);
    // Underscored profile ids + missing channels.
    expect(
      findTileIndex(const ValueKey('tile_my_home_dvr_4_sd'), [4]),
      0,
    );
    expect(findTileIndex(const ValueKey('tile_abc_9_hd'), channels), isNull);
    expect(findTileIndex(const ValueKey('nope'), channels), isNull);
  });

  test('RtspOpener caps concurrency and admits FIFO', () async {
    final admitted = <int>[];
    var active = 0;
    var maxActive = 0;
    final gates = List.generate(5, (_) => Completer<void>());
    Future<void> task(int i) => RtspOpener.run(() async {
          active++;
          if (active > maxActive) maxActive = active;
          admitted.add(i);
          await gates[i].future;
          active--;
        });

    final futures = [for (var i = 0; i < 5; i++) task(i)];
    // run() bodies execute synchronously to the first await: the first
    // three tasks must already hold the three slots, in call order.
    expect(admitted, [0, 1, 2]);
    for (final g in gates) {
      g.complete();
      // Let completions + queued admissions flush through the event loop.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future.wait(futures);
    expect(admitted, [0, 1, 2, 3, 4]);
    expect(maxActive, lessThanOrEqualTo(RtspOpener.maxConcurrent));
    expect(RtspOpener.isQuiescent, isTrue);
  });

  testWidgets('App boots to an empty profile list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CctvApp());
    await tester.pump(); // ProfilesCubit.load()
    await tester.pump(const Duration(milliseconds: 300)); // AnimatedSwitcher

    expect(find.byType(ProfileListPage), findsOneWidget);
    expect(find.text('DVR Profiles'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty')), findsOneWidget);

    final context = tester.element(find.byKey(const ValueKey('empty')));
    final cubit = BlocProvider.of<ProfilesCubit>(context);
    expect(cubit.state.status, ProfilesStatus.loaded);
    expect(cubit.state.profiles, isEmpty);
    expect(cubit.state.error, isNull);
  });
}

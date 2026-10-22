import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'rtsp_url.dart';

/// Outcome of a one-shot RTSP handshake used to validate a DVR profile
/// before it is saved.
enum RtspProbeStatus {
  ok,
  unreachable,
  timeout,
  authFailed,
  streamUnavailable,
  badResponse,
}

/// User-facing result of [RtspProbe.probe].
///
/// [message] never contains credentials — only the host/port the user typed.
class RtspProbeResult {
  final RtspProbeStatus status;
  final String message;

  const RtspProbeResult(this.status, this.message);

  bool get ok => status == RtspProbeStatus.ok;

  @override
  String toString() => message;
}

/// Validates host/port/credentials by sending an RTSP `DESCRIBE` for the
/// profile's first sub-stream channel.
///
/// This is the same request media_kit/libmpv makes before opening a stream,
/// but without spawning a player: it proves the DVR is reachable, the port is
/// an RTSP server, and the username/password are accepted. Basic auth is
/// tried first, then Digest/MD5 if the DVR challenges for it (Dahua/CP Plus
/// devices use either depending on firmware). Pure `dart:io`, so it is unit
/// testable against a fake RTSP server.
class RtspProbe {
  final Duration timeout;

  const RtspProbe({this.timeout = const Duration(seconds: 8)});

  Future<RtspProbeResult> probe({
    required String host,
    required int port,
    required String user,
    required String password,
    int channelOneBased = 1,
  }) async {
    final target = _Target(
      host: host,
      port: port,
      uri: 'rtsp://$host:$port'
          '${dahuaRtspPath(channelOneBased: channelOneBased, highRes: false)}',
    );
    try {
      var response = await _describe(
        target,
        authorization: _basicAuth(user, password),
      );
      if (response.status == 401) {
        final challenge = response.digestChallenge;
        if (challenge != null) {
          final auth = _digestAuth(
            user: user,
            password: password,
            uri: target.uri,
            challenge: challenge,
          );
          if (auth != null) {
            response = await _describe(target, authorization: auth);
          }
        }
      }
      return _resultFor(response, target);
    } on TimeoutException {
      return RtspProbeResult(
        RtspProbeStatus.timeout,
        'No RTSP response from ${target.host}:${target.port} — '
        'check the IP, port, and network.',
      );
    } on SocketException {
      return RtspProbeResult(
        RtspProbeStatus.unreachable,
        "Can't reach ${target.host}:${target.port} — check the IP and port.",
      );
    } on _ProbeException {
      return RtspProbeResult(
        RtspProbeStatus.unreachable,
        '${target.host}:${target.port} closed the RTSP connection — '
        'is this an RTSP port?',
      );
    }
  }

  Future<_RtspResponse> _describe(
    _Target target, {
    String? authorization,
  }) async {
    final socket = await Socket.connect(
      target.connectHost,
      target.port,
      timeout: timeout,
    );
    final received = Completer<String>();
    final bytes = <int>[];
    late final StreamSubscription<List<int>> sub;

    sub = socket.listen(
      (chunk) {
        bytes.addAll(chunk);
        // latin1 maps 1 byte to 1 char, so chunk boundaries can never split
        // a decoded character and hide the header terminator.
        final text = latin1.decode(bytes);
        final end = text.indexOf('\r\n\r\n');
        if (end >= 0 && !received.isCompleted) {
          received.complete(text.substring(0, end));
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!received.isCompleted) received.completeError(error, stack);
      },
      onDone: () {
        if (!received.isCompleted) {
          received.completeError(
            const _ProbeException('closed'),
            StackTrace.current,
          );
        }
      },
      cancelOnError: true,
    );

    try {
      socket.add(utf8.encode(_request(target, authorization)));
      await socket.flush();
      final headers = await received.future.timeout(timeout);
      return _RtspResponse.parse(headers);
    } finally {
      await sub.cancel();
      socket.destroy();
    }
  }

  String _request(_Target target, String? authorization) {
    final request = StringBuffer()
      ..write('DESCRIBE ${target.uri} RTSP/1.0\r\n')
      ..write('CSeq: 1\r\n')
      ..write('Accept: application/sdp\r\n')
      ..write('User-Agent: gCMOB-Reimagined\r\n');
    if (authorization != null) {
      request.write('Authorization: $authorization\r\n');
    }
    request.write('\r\n');
    return request.toString();
  }

  RtspProbeResult _resultFor(_RtspResponse response, _Target target) {
    switch (response.status) {
      case 200:
        return RtspProbeResult(
          RtspProbeStatus.ok,
          'Connected to ${target.host}:${target.port}.',
        );
      case 401:
      case 403:
        return const RtspProbeResult(
          RtspProbeStatus.authFailed,
          'The DVR rejected the username or password.',
        );
      case 404:
      case 455:
        return RtspProbeResult(
          RtspProbeStatus.streamUnavailable,
          'DVR reachable, but channel 1 is unavailable on it.',
        );
      default:
        if (response.status >= 500) {
          return RtspProbeResult(
            RtspProbeStatus.badResponse,
            'The DVR returned an RTSP error (${response.status}).',
          );
        }
        return RtspProbeResult(
          RtspProbeStatus.badResponse,
          'Unexpected RTSP response (${response.status}) from '
          '${target.host}:${target.port}.',
        );
    }
  }
}

String _basicAuth(String user, String password) =>
    'Basic ${base64Encode(utf8.encode('$user:$password'))}';

String _md5(String input) => md5.convert(utf8.encode(input)).toString();

String? _digestAuth({
  required String user,
  required String password,
  required String uri,
  required String challenge,
}) {
  const method = 'DESCRIBE';
  final params = _digestParams(challenge);
  final realm = params['realm'];
  final nonce = params['nonce'];
  if (realm == null || nonce == null) return null;

  // MD5 only: what DVRs ship. Unsupported algorithms fall through to the
  // server's own 401 so the user sees "credentials rejected" instead of a
  // silently wrong hash.
  final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
  if (algorithm != 'MD5') return null;

  final offeredQop = params['qop']
          ?.split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e == 'auth')
          .toList() ??
      const <String>[];
  final useQop = offeredQop.isNotEmpty;
  final nc = '00000001';
  final cnonce = _randomHex(8);

  final ha1 = _md5('$user:$realm:$password');
  final ha2 = _md5('$method:$uri');
  final response = useQop
      ? _md5('$ha1:$nonce:$nc:$cnonce:auth:$ha2')
      : _md5('$ha1:$nonce:$ha2');

  final fields = <String>[
    'username="${_quote(user)}"',
    'realm="${_quote(realm)}"',
    'nonce="${_quote(nonce)}"',
    'uri="${_quote(uri)}"',
    'response="$response"',
    if (params['opaque'] != null) 'opaque="${_quote(params['opaque']!)}"',
    if (useQop) 'qop=auth',
    if (useQop) 'nc=$nc',
    if (useQop) 'cnonce="$cnonce"',
  ];
  return 'Digest ${fields.join(', ')}';
}

Map<String, String> _digestParams(String challenge) {
  final params = <String, String>{};
  final pattern = RegExp(r'([a-zA-Z0-9_-]+)\s*=\s*("(?:[^"\\]|\\.)*"|[^,\s]+)');
  for (final match in pattern.allMatches(challenge)) {
    var value = match.group(2)!;
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).replaceAll(r'\"', '"');
    }
    params[match.group(1)!.toLowerCase()] = value;
  }
  return params;
}

String _quote(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class _Target {
  final String host;
  final int port;
  final String uri;

  const _Target({required this.host, required this.port, required this.uri});

  /// `Socket.connect` wants bare IPv6 literals; the RTSP URI keeps brackets.
  String get connectHost =>
      host.startsWith('[') && host.endsWith(']')
          ? host.substring(1, host.length - 1)
          : host;
}

class _RtspResponse {
  final int status;
  final Map<String, List<String>> headers;

  const _RtspResponse(this.status, this.headers);

  factory _RtspResponse.parse(String raw) {
    final lines = raw.split('\r\n');
    final statusLine = lines.first.trim();
    final parts = statusLine.split(RegExp(r'\s+'));
    final status = parts.length > 1 ? int.tryParse(parts[1]) ?? -1 : -1;

    final headers = <String, List<String>>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      headers.putIfAbsent(name, () => []).add(value);
    }
    return _RtspResponse(status, headers);
  }

  /// The first Digest challenge, if the DVR offered one. Servers may send
  /// Basic and Digest in separate headers, in either order.
  String? get digestChallenge {
    for (final value in headers['www-authenticate'] ?? const <String>[]) {
      if (value.toLowerCase().startsWith('digest')) return value;
    }
    return null;
  }
}

class _ProbeException implements Exception {
  final String message;

  const _ProbeException(this.message);

  @override
  String toString() => message;
}

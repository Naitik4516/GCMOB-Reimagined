import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/core/rtsp/rtsp_probe.dart';

typedef _Handler = Future<void> Function(String request, Socket socket);

/// Minimal RTSP server for probe tests: one request per connection, scripted
/// response, requests recorded verbatim.
class _FakeDvr {
  _FakeDvr._(this._server, this._handler);

  final ServerSocket _server;
  final _Handler _handler;
  final List<String> requests = [];
  final List<Socket> _sockets = [];

  static Future<_FakeDvr> start(_Handler handler) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final dvr = _FakeDvr._(server, handler);
    dvr._listen();
    return dvr;
  }

  void _listen() {
    _server.listen((socket) {
      _sockets.add(socket);
      final bytes = <int>[];
      var handled = false;
      socket.listen((chunk) async {
        bytes.addAll(chunk);
        final text = latin1.decode(bytes);
        if (handled || !text.contains('\r\n\r\n')) return;
        handled = true;
        requests.add(text);
        await _handler(text, socket);
      });
    });
  }

  int get port => _server.port;

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

Future<void> _respond(
  Socket socket,
  String status, {
  List<String> headers = const [],
  String body = '',
}) async {
  final response = StringBuffer('RTSP/1.0 $status\r\nCSeq: 1\r\n');
  for (final header in headers) {
    response.write('$header\r\n');
  }
  response.write('Content-Length: ${body.length}\r\n\r\n$body');
  socket.add(latin1.encode(response.toString()));
  await socket.flush();
  await socket.close();
}

String _header(String request, String name) {
  for (final line in request.split('\r\n')) {
    if (line.toLowerCase().startsWith('${name.toLowerCase()}:')) {
      return line.substring(line.indexOf(':') + 1).trim();
    }
  }
  return '';
}

const _timeout = Duration(seconds: 2);

Future<RtspProbeResult> _probe(int port, {String password = 'secret'}) {
  return const RtspProbe(timeout: _timeout).probe(
    host: '127.0.0.1',
    port: port,
    user: 'admin',
    password: password,
  );
}

void main() {
  test('DESCRIBE 200 means the profile is valid', () async {
    final dvr = await _FakeDvr.start(
      (request, socket) => _respond(socket, '200 OK', body: 'v=0\r\n'),
    );
    addTearDown(dvr.close);

    final result = await _probe(dvr.port);

    expect(result.status, RtspProbeStatus.ok);
    expect(result.message, contains('127.0.0.1:${dvr.port}'));
    expect(dvr.requests, hasLength(1));

    final request = dvr.requests.single;
    expect(
      request,
      startsWith(
        'DESCRIBE rtsp://127.0.0.1:${dvr.port}'
        '/cam/realmonitor?channel=0&subtype=1 RTSP/1.0',
      ),
    );
    expect(
      _header(request, 'authorization'),
      'Basic ${base64Encode(utf8.encode('admin:secret'))}',
    );
  });

  test('401 with a Basic challenge reports rejected credentials', () async {
    final dvr = await _FakeDvr.start(
      (request, socket) => _respond(
        socket,
        '401 Unauthorized',
        headers: ['WWW-Authenticate: Basic realm="DVR"'],
      ),
    );
    addTearDown(dvr.close);

    final result = await _probe(dvr.port);

    expect(result.status, RtspProbeStatus.authFailed);
    expect(result.message, contains('username or password'));
    // Basic is not retried: one request is enough to know it failed.
    expect(dvr.requests, hasLength(1));
  });

  test('Digest challenge is retried with a correct MD5 response', () async {
    var attempts = 0;
    final dvr = await _FakeDvr.start((request, socket) async {
      attempts++;
      if (attempts == 1) {
        await _respond(
          socket,
          '401 Unauthorized',
          headers: [
            'WWW-Authenticate: Digest realm="DVR", nonce="abc123", '
                'qop="auth", opaque="op1"',
          ],
        );
        return;
      }
      await _respond(socket, '200 OK');
    });
    addTearDown(dvr.close);

    final result = await _probe(dvr.port);

    expect(result.status, RtspProbeStatus.ok);
    expect(attempts, 2);

    final authorization = _header(dvr.requests[1], 'authorization');
    expect(authorization, startsWith('Digest '));
    expect(authorization, contains('username="admin"'));
    expect(authorization, contains('realm="DVR"'));
    expect(authorization, contains('nonce="abc123"'));
    expect(authorization, contains('opaque="op1"'));

    final cnonce = RegExp(r'cnonce="([^"]+)"').firstMatch(authorization)!
        .group(1)!;
    final nc = RegExp(r'nc=([0-9a-f]+)').firstMatch(authorization)!.group(1)!;
    final response = RegExp(r'response="([^"]+)"')
        .firstMatch(authorization)!
        .group(1)!;
    final uri = 'rtsp://127.0.0.1:${dvr.port}'
        '/cam/realmonitor?channel=0&subtype=1';
    String hash(String input) => md5.convert(utf8.encode(input)).toString();
    final ha1 = hash('admin:DVR:secret');
    final ha2 = hash('DESCRIBE:$uri');
    expect(response, hash('$ha1:abc123:$nc:$cnonce:auth:$ha2'));
  });

  test('404 reports a reachable DVR without the channel', () async {
    final dvr = await _FakeDvr.start(
      (request, socket) => _respond(socket, '404 Not Found'),
    );
    addTearDown(dvr.close);

    final result = await _probe(dvr.port);

    expect(result.status, RtspProbeStatus.streamUnavailable);
    expect(result.message, contains('channel 1'));
  });

  test('closed port reports unreachable', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();

    final result = await _probe(port);

    expect(result.status, RtspProbeStatus.unreachable);
    expect(result.message, contains('check the IP and port'));
  });

  test('silent server reports a timeout', () async {
    final dvr = await _FakeDvr.start((request, socket) async {});
    addTearDown(dvr.close);

    final result = await const RtspProbe(
      timeout: Duration(milliseconds: 150),
    ).probe(
      host: '127.0.0.1',
      port: dvr.port,
      user: 'admin',
      password: 'secret',
    );

    expect(result.status, RtspProbeStatus.timeout);
  });

  test('probe messages never echo the password', () async {
    final dvr = await _FakeDvr.start(
      (request, socket) => _respond(socket, '401 Unauthorized'),
    );
    addTearDown(dvr.close);

    final result = await _probe(dvr.port, password: 'super-secret-pass');

    expect(result.message, isNot(contains('super-secret-pass')));
  });
}

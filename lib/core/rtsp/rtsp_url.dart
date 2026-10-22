/// Dahua / CP Plus RTSP URL builder.
///
/// DVR quirk: the `channel=` query param is **0-indexed** while the UI
/// shows 1-indexed channel numbers. UI channel 1 => `channel=0`.
library;

/// Dahua stream path + query, without scheme/authority.
///
/// Shared by [buildDahuaRtsp] and the connection probe so both request the
/// exact same stream.
String dahuaRtspPath({
  required int channelOneBased,
  required bool highRes,
}) {
  final subtype = highRes ? 0 : 1;
  final channelZeroBased = channelOneBased - 1;
  return '/cam/realmonitor?channel=$channelZeroBased&subtype=$subtype';
}

/// Builds a Dahua/CP Plus `realmonitor` RTSP URL.
///
/// * [channelOneBased] — 1-based channel number shown in the UI (1..N).
/// * [highRes] — `false` => sub-stream (`subtype=1`, grid),
///   `true` => main-stream (`subtype=0`, fullscreen).
String buildDahuaRtsp({
  required String user,
  required String pass,
  required String host,
  required int port,
  required int channelOneBased,
  required bool highRes,
}) {
  final u = Uri.encodeComponent(user);
  final p = Uri.encodeComponent(pass);
  return 'rtsp://$u:$p@$host:$port'
      '${dahuaRtspPath(channelOneBased: channelOneBased, highRes: highRes)}';
}

final RegExp _rtspSchemePrefix =
    RegExp(r'^rtsp://', caseSensitive: false);
final RegExp _bracketedHost = RegExp(r'^\[[^\]]+\](?::\d+)?$');
final RegExp _bracketedHostWithPort = RegExp(r'^\[[^\]]+\]:\d+$');
final RegExp _whitespace = RegExp(r'\s');
final RegExp _hostTerminator = RegExp(r'[/?#]');

/// Normalizes a user-entered DVR host for [buildDahuaRtsp].
///
/// Accepts hostnames, IPv4, bare/bracketed IPv6, and pasted
/// `rtsp://host/...` values. Credentials and a separate `:port` are rejected
/// because the form has dedicated fields for them.
///
/// Throws [FormatException] with a user-facing message.
String normalizeRtspHost(String raw) {
  var value = raw.trim();
  if (value.isEmpty) {
    throw const FormatException('Enter the DVR IP address or hostname');
  }

  value = value.replaceFirst(_rtspSchemePrefix, '');
  final cut = value.indexOf(_hostTerminator);
  if (cut >= 0) value = value.substring(0, cut);
  value = value.trim();
  if (value.isEmpty) {
    throw const FormatException('Enter the DVR IP address or hostname');
  }
  if (value.contains('@')) {
    throw const FormatException('Remove user:pass@ from the host field');
  }
  if (_whitespace.hasMatch(value)) {
    throw const FormatException('Host cannot contain spaces');
  }

  if (value.startsWith('[')) {
    if (!_bracketedHost.hasMatch(value)) {
      throw const FormatException('Invalid bracketed IPv6 host');
    }
    if (_bracketedHostWithPort.hasMatch(value)) {
      throw const FormatException('Put the port in the RTSP Port field');
    }
    return value;
  }

  final colons = ':'.allMatches(value).length;
  if (colons == 1) {
    throw const FormatException(
        'Enter a hostname, IPv4, or IPv6 address without a port');
  }
  // A bare IPv6 literal needs brackets in the URL authority.
  if (colons >= 2) return '[$value]';
  return value;
}

final RegExp _schemeCredentials = RegExp(
  r'([a-zA-Z][a-zA-Z0-9+.-]*://)([^/\s@]+)@',
);
final RegExp _bareCredentials = RegExp(r'(?<![\w/])([^/\s:@]+):([^/\s@]+)@');

/// Hides `user:pass@` from messages that may be shown in the UI or logs.
///
/// The player still needs the real URL; this is display-only.
String redactRtspCredentials(String message) {
  // Bare credentials first: once a scheme URL has been replaced, re-running
  // the bare pattern on `***:***@` would redact the placeholders again.
  var redacted = message.replaceAllMapped(
    _bareCredentials,
    (_) => '***:***@',
  );
  redacted = redacted.replaceAllMapped(
    _schemeCredentials,
    (m) => '${m[1]}***:***@',
  );
  return redacted;
}

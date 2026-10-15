/// Dahua / CP Plus RTSP URL builder.
///
/// DVR quirk: the `channel=` query param is **0-indexed** while the UI
/// shows 1-indexed channel numbers. UI channel 1 => `channel=0`.
library;

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
  final subtype = highRes ? 0 : 1;
  final channelZeroBased = channelOneBased - 1;
  return 'rtsp://$u:$p@$host:$port/cam/realmonitor'
      '?channel=$channelZeroBased&subtype=$subtype';
}

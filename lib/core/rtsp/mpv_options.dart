/// Low-latency libmpv option constants applied before `Player.open()`.
library;

/// TCP transport kills the UDP `nan` / frozen-frame issue on Wi-Fi.
const kRtspTransport = MapEntry('rtsp-transport', 'tcp');

/// Ordered libmpv properties for sub-stream grid playback.
const kLowLatencyMpvOptions = <MapEntry<String, String>>[
  MapEntry('rtsp-transport', 'tcp'),
  MapEntry('cache', 'no'),
  MapEntry('nobuffer', 'yes'),
  MapEntry('flags', 'low_delay'),
  MapEntry('probesize', '32'),
  MapEntry('analyzeduration', '0'),
  // Auto-reconnect so a dropped tile recovers without user action.
  MapEntry('reconnect', 'yes'),
];

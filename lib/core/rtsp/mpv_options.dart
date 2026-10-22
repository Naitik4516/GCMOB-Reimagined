/// Low-latency libmpv option constants applied before `Player.open()`.
library;

/// Ordered libmpv properties for low-latency RTSP playback.
///
/// Recovery is user-initiated (`TileCubit.retry`); `_fail` stops the player,
/// so mpv's own reconnect loop must stay off. Enabling `reconnect=yes` here
/// would let a dead tile keep holding a DVR session behind the error overlay.
const kLowLatencyMpvOptions = <MapEntry<String, String>>[
  MapEntry('rtsp-transport', 'tcp'),
  MapEntry('cache', 'no'),
  MapEntry('nobuffer', 'yes'),
  MapEntry('flags', 'low_delay'),
  MapEntry('probesize', '32'),
  MapEntry('analyzeduration', '0'),
];

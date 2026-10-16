/// Classifies mpv log lines forwarded to `Player.stream.error`.
///
/// media_kit forwards EVERY mpv log at `error` level (prefixes `cplayer`,
/// `stream`, `vd`, `ad`, …) to the error stream — including routine seek
/// notes emitted while playback otherwise continues (e.g. the internal
/// play-after-EOF seek, demuxer probes, and the standalone
/// `--force-seekable` hint line, which never contains the words "cannot
/// seek" itself). On a live, non-seekable RTSP stream ANY seek-related
/// note is unactionable by definition, so all of them are benign.
bool isBenignLiveError(String message) =>
    message.toLowerCase().contains('seek');

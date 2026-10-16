import 'dart:async';

/// Serializes RTSP `open()` calls across all tiles.
///
/// A 3x3 grid fires up to 9 simultaneous handshakes at a cheap DVR/NVR,
/// which chokes its tiny CPU and session table — every stream gets slow
/// instead of a few getting fast. This FIFO gate admits at most
/// [maxConcurrent] concurrent opens; the `playing` wait happens outside
/// the gate, so a slot is only held for the handshake itself.
///
/// Callers must not hold grid state hostage: keep the task to
/// apply-flags + `Player.open`, nothing more.
class RtspOpener {
  /// Concurrent handshakes. 3 keeps a 4/8/16ch DVR responsive while a
  /// 9-tile page still fills within a few seconds.
  static const int maxConcurrent = 3;

  static int _active = 0;
  static final List<Completer<void>> _queue = [];

  static Future<T> run<T>(Future<T> Function() task) async {
    while (_active >= maxConcurrent) {
      final gate = Completer<void>();
      _queue.add(gate);
      await gate.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }

  /// Test hook: true while no open is in flight or queued.
  static bool get isQuiescent => _active == 0 && _queue.isEmpty;
}

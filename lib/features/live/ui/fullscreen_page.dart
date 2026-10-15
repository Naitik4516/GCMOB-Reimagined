import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/rtsp/rtsp_url.dart';
import '../../profiles/models/dvr_profile.dart';
import '../bloc/tile_cubit.dart';
import '../player/media_kit_rtsp_controller.dart';

/// Fullscreen single camera.
///
/// Seamless handoff: opens instantly on the grid tile's already-playing
/// sub-stream ([TileCubit] keeps owning that player), loads the HD
/// main-stream (`subtype=0`) in the background, and swaps layers once it
/// produces frames. The sub-stream decoder is released at swap time and
/// restarted when this page closes, so the grid tile recovers with a
/// spinner instead of a black hole. Remote Back pops to grid.
class FullscreenPage extends StatefulWidget {
  final DvrProfile profile;
  final String password;
  final int channel;
  final TileCubit tileCubit;

  const FullscreenPage({
    super.key,
    required this.profile,
    required this.password,
    required this.channel,
    required this.tileCubit,
  });

  @override
  State<FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<FullscreenPage> {
  static const _switchWatchdog = Duration(seconds: 15);

  MediaKitRTSPController? _main;
  bool _mainReady = false;
  bool _mainError = false;
  String _mainErrorMsg = '';
  bool _hd = true;
  bool _switching = false;
  bool _mainPlaying = false;
  bool _mainSized = false;
  int _switchGen = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _openMain();
  }

  String _url(bool hd) => buildDahuaRtsp(
        user: widget.profile.username,
        pass: widget.password,
        host: widget.profile.host,
        port: widget.profile.rtspPort,
        channelOneBased: widget.channel,
        highRes: hd,
      );

  Future<void> _openMain() async {
    final c = MediaKitRTSPController(hwdec: 'auto-safe', muted: false);
    setState(() => _main = c);
    c.player.stream.playing.listen((playing) {
      if (!mounted || !playing) return;
      _mainPlaying = true;
      _maybeMainReady();
    });
    // Like the grid tiles: `playing` precedes the first decoded frame,
    // so the swap waits for sized frames instead of flashing black.
    c.player.stream.width.listen((w) {
      if (!mounted) return;
      if ((w ?? 0) > 0) {
        _mainSized = true;
        _maybeMainReady();
      }
    });
    c.player.stream.error.listen((e) {
      if (!mounted || e.isEmpty) return;
      setState(() {
        _mainError = true;
        _mainErrorMsg = e;
        _switching = false;
      });
    });
    try {
      await c.openMain(_url(_hd), withAudio: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mainError = true;
          _mainErrorMsg = '$e';
        });
      }
    }
  }

  /// Main stream has sized frames: take over and release the sub decoder.
  void _maybeMainReady() {
    if (!_mainPlaying || !_mainSized || !mounted) return;
    widget.tileCubit.suspend();
    if (!_mainReady || _switching || _mainError) {
      setState(() {
        _mainReady = true;
        _mainError = false;
        _switching = false;
      });
    }
  }

  Future<void> _retryMain() async {
    final c = _main;
    if (c == null) return;
    setState(() => _mainError = false);
    _mainPlaying = false;
    _mainSized = false;
    try {
      await c.openMain(_url(_hd), withAudio: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mainError = true;
          _mainErrorMsg = '$e';
        });
      }
    }
  }

  Future<void> _switchQuality(bool hd) async {
    final c = _main;
    if (c == null || hd == _hd || _switching) return;
    final gen = ++_switchGen;
    // The old stream unloads immediately; keep a small status chip up
    // (the last frame typically freezes underneath, no blocking spinner).
    setState(() {
      _switching = true;
      _mainError = false;
      _hd = hd;
    });
    _mainPlaying = false;
    _mainSized = false;
    // Watchdog: a hung load falls back to the previous quality instead
    // of sitting on a frozen frame forever.
    Future<void>.delayed(_switchWatchdog).then((_) {
      if (!mounted || gen != _switchGen || !_switching) return;
      _revertSwitch(gen);
    });
    try {
      await c.openSingle(_url(hd), withAudio: true);
    } catch (_) {
      if (mounted && gen == _switchGen) _revertSwitch(gen);
    }
  }

  void _revertSwitch(int gen) {
    final c = _main;
    if (c == null || gen != _switchGen) return;
    final prev = !_hd;
    setState(() => _hd = prev);
    c.openSingle(_url(prev), withAudio: true).then((_) {}, onError: (_) {
      if (mounted && gen == _switchGen) {
        setState(() {
          _switching = false;
          _mainError = true;
          _mainErrorMsg = 'Stream unavailable';
        });
      }
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _main?.dispose();
    // Grid tile restarts its sub-stream unless it never stopped.
    widget.tileCubit.ensureSubPlaying();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showChip = (!_mainReady && !_mainError) || _switching;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('CH ${widget.channel} — ${widget.profile.name}'),
        actions: [
          // SD / HD segmented switch.
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('SD')),
              ButtonSegment(value: true, label: Text('HD')),
            ],
            selected: {_hd},
            onSelectionChanged: (s) => _switchQuality(s.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: 'Audio on (grid is muted)',
            onPressed: () => _main?.player.setVolume(100.0),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Base layer: the grid sub-stream, already playing. Stays up
          // until the main stream produces its first frame.
          if (!_mainReady)
            Video(
              controller: widget.tileCubit.controller.videoController,
              controls: NoVideoControls,
              pauseUponEnteringBackgroundMode: false,
            ),
          if (_mainReady && _main != null)
            Video(
              controller: _main!.videoController,
              controls: NoVideoControls,
              pauseUponEnteringBackgroundMode: false,
            ),
          if (showChip)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _switching
                            ? 'Switching to ${_hd ? 'HD' : 'SD'}…'
                            : 'Loading ${_hd ? 'HD' : 'SD'}…',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_mainError && !_mainReady)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off,
                        color: Colors.redAccent, size: 40),
                    const SizedBox(height: 8),
                    const Text(
                      'HD stream failed — still showing SD.',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _mainErrorMsg,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      autofocus: true,
                      onPressed: _retryMain,
                      child: const Text('Retry HD'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/adaptive_shell.dart';
import '../../../app/theme.dart';
import '../../../core/platform/app_chrome.dart';
import '../../../core/platform/app_fullscreen.dart';
import '../../../core/platform/is_tv.dart';
import '../../profiles/data/profile_store.dart';
import '../../profiles/models/dvr_profile.dart';
import '../bloc/grid_cubit.dart';
import 'camera_grid_widget.dart';
import 'live_controls.dart';

/// Live view: [CameraGridWidget] + controls.
///
/// * Phone portrait (bottom bar): layout picker, SD/HD, paging. The top
///   bar keeps title + fullscreen only so it fits narrow screens.
/// * Phone landscape: ultra-immersive — bars hidden, fling to turn pages,
///   tap reveals a floating bar + back button. Kicks in only after the
///   device has shown portrait once, so landscape-locked TVs never enter.
/// * Desktop (title bar): layout picker, SD/HD, shortcuts help and
///   fullscreen live in the window title bar; paging floats carousel
///   style over the grid edges. No bottom bar.
/// * TV keeps the phone-portrait layout (bottom bar is D-Pad focusable).
///
/// Reordering needs no mode switch: drag-and-drop on touch, right-click
/// channel picker on desktop, hold-OK grab-and-drop on TV remotes.
class LivePage extends StatefulWidget {
  final DvrProfile profile;
  final String password;

  const LivePage({super.key, required this.profile, required this.password});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  /// True once a portrait layout was seen: the device can rotate, so it
  /// is a phone/tablet rather than a landscape-locked TV.
  bool _seenPortrait = false;

  /// Phone-landscape ultra-immersive mode (bars hidden, swipe pages).
  bool _immersive = false;

  bool _controlsVisible = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_immersive) {
      // Popping/Back while landscape must restore the system bars for the
      // profile list too; the route's state is gone before the next frame.
      _immersive = false;
      unawaited(AppChrome.setPageImmersive(false));
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Field assignment, no setState: this runs before build.
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (!landscape) {
      _seenPortrait = true;
      if (_immersive) {
        _immersive = false;
        _controlsVisible = false;
        _hideTimer?.cancel();
        // The reconciler keeps immersion if app fullscreen is still on.
        unawaited(AppChrome.setPageImmersive(false));
      }
    } else if (_seenPortrait && !_immersive && !isDesktopDevice) {
      _immersive = true;
      _showImmersiveControls();
      unawaited(AppChrome.setPageImmersive(true));
    }
  }

  void _showImmersiveControls() {
    if (!_immersive || !mounted) return;
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _immersive) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _immersiveBack(BuildContext gridContext) {
    final grid = gridContext.read<GridCubit>();
    if (grid.state.isFocused) {
      grid.unfocus();
    } else {
      Navigator.of(gridContext).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GridCubit(
        store: ProfileStore(),
        profileId: widget.profile.id,
        gridSize: 4,
        channelCount: widget.profile.channelCount,
      )..restore(),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final desktop = isDesktopDevice;
          return AdaptiveShell(
            title: widget.profile.name,
            titleTrailing: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.onPrimaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (desktop)
                const LiveControls(showShortcuts: true),
              const _FullscreenToggle(),
            ],
            hideChrome: _immersive,
            body: desktop
                ? _DesktopBody(
                    profile: widget.profile,
                    password: widget.password)
                : _PhoneBody(
                    profile: widget.profile,
                    password: widget.password,
                    immersive: _immersive,
                    controlsVisible: _controlsVisible,
                    onTap: _showImmersiveControls,
                    onBack: () => _immersiveBack(context),
                  ),
            bottomBar:
                (desktop || _immersive) ? null : const _LiveControlBar(),
          );
        },
      ),
    );
  }
}

class _FullscreenToggle extends StatelessWidget {
  const _FullscreenToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppFullscreen.isFullscreen,
      builder: (_, full, child) => IconButton(
        tooltip: full ? 'Exit fullscreen (F11)' : 'Fullscreen (F11)',
        icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen),
        onPressed: () => AppFullscreen.toggle(),
      ),
    );
  }
}

/// Phone body: the SAME [CameraGridWidget] element in every mode.
///
/// Shape stability is load-bearing: rotation toggles immersive chrome,
/// but the grid must never remount — remounting disposes every
/// TileCubit and all streams reload (visible in logcat as a wave of
/// MediaCodec teardowns). Immersive layers are appended AFTER the grid
/// so child 0 is untouched; the tap layer only listens for taps and
/// never competes with drag/scale gestures.
class _PhoneBody extends StatelessWidget {
  final DvrProfile profile;
  final String password;
  final bool immersive;
  final bool controlsVisible;
  final VoidCallback onTap;
  final VoidCallback onBack;

  const _PhoneBody({
    required this.profile,
    required this.password,
    required this.immersive,
    required this.controlsVisible,
    required this.onTap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraGridWidget(
            profile: profile,
            password: password,
            immersive: immersive),
        // Tap-to-reveal layer: the translucent hit-test layer wins single
        // taps (reveal controls). It deliberately claims no double-tap or
        // drag gestures, so those still reach the tile. Do not assume a
        // single tap focuses a tile while immersive controls are hidden.
        if (immersive)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onTap,
              child: const SizedBox.expand(),
            ),
          ),
        if (immersive && controlsVisible) ...[
          Positioned(
            top: 12,
            left: 12,
            child: _FloatBtn(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: onBack,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(child: _ImmersiveBar(onBack: onBack)),
          ),
        ],
      ],
    );
  }
}

class _FloatBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _FloatBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        color: Colors.white,
        onPressed: onPressed,
      ),
    );
  }
}

/// Floating translucent pager: layout picker, SD/HD (1x1), prev/next
/// (hidden at the ends — no disabled dead-ends), plus a Grid exit while
/// a channel is focused.
class _ImmersiveBar extends StatelessWidget {
  final VoidCallback onBack;

  const _ImmersiveBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: LiveControls(
        showPager: true,
        showPageLabel: true,
        showGridExit: true,
        onGridExit: onBack,
        iconColor: Colors.white,
      ),
    );
  }
}

/// Desktop body: grid + floating carousel pager over the grid edges.
/// Edge buttons hide at the ends instead of sitting disabled.
class _DesktopBody extends StatelessWidget {
  final DvrProfile profile;
  final String password;

  const _DesktopBody({required this.profile, required this.password});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GridCubit, GridState>(
      builder: (context, grid) {
        final cubit = context.read<GridCubit>();
        final page = grid.displayPage;
        return Stack(
          children: [
            CameraGridWidget(profile: profile, password: password),
            if (grid.pageCount > 1 && page > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _PagerBtn(
                    icon: Icons.chevron_left,
                    tooltip: 'Previous page',
                    onPressed: () => cubit.prevPage(),
                  ),
                ),
              ),
            if (grid.pageCount > 1 && page < grid.pageCount - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _PagerBtn(
                    icon: Icons.chevron_right,
                    tooltip: 'Next page',
                    onPressed: () => cubit.nextPage(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PagerBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PagerBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 28),
        color: Colors.white,
        onPressed: onPressed,
      ),
    );
  }
}

/// Phone-portrait (/TV) bottom control bar: layout picker, SD/HD (1x1),
/// paging. Chevron buttons hide at the ends instead of sitting disabled.
/// Horizontally scrollable for narrow phones. No Grid-exit button (exit
/// via double-tap / Back) and no shortcuts button (desktop only).
class _LiveControlBar extends StatelessWidget {
  const _LiveControlBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CctvTheme.surfaceLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: const LiveControls(
            showPager: true,
            showPageLabel: true,
          ),
        ),
      ),
    );
  }
}

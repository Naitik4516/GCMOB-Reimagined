import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../profiles/data/profile_store.dart';

/// Grid layout: 1, 4, or 9 visible tiles + page index for >9 channels.
///
/// * [order] — user-arranged display order (persisted per profile). Tile
///   positions NEVER change on their own: a stream failing or recovering
///   leaves the slot exactly where the user put it.
/// * [focusedChannel] — a double-clicked/OK tile is shown alone (1x1, HD).
///   [layoutSize] and [page] stay untouched, so exiting returns exactly to
///   the grid the user left. Null means the normal grid.
/// * [singleHd] — 1x1 tiles play the HD main-stream (audio on); off to
///   force SD.
class GridState extends Equatable {
  /// The user's chosen layout (1, 4 or 9), persisted.
  final int layoutSize;
  final int page;
  final int channelCount;
  final List<int> order;

  /// 1-based channel shown alone, or null for the normal grid.
  final int? focusedChannel;

  final bool singleHd;

  const GridState({
    this.layoutSize = 4,
    this.page = 0,
    required this.channelCount,
    required this.order,
    this.focusedChannel,
    this.singleHd = true,
  });

  /// Visible layout. Focus forces 1x1 without changing [layoutSize].
  int get gridSize => focusedChannel != null ? 1 : layoutSize;

  bool get isFocused => focusedChannel != null;

  int get pageCount =>
      channelCount <= gridSize ? 1 : (channelCount / gridSize).ceil();

  /// Grid page, or the focused channel's position while focused. Pager
  /// labels/chevrons use this so 1x1 surfing still reports a position.
  int get displayPage =>
      focusedChannel != null ? order.indexOf(focusedChannel!) : page;

  /// 1-based channels visible on the current page.
  List<int> get visibleChannels {
    final focused = focusedChannel;
    if (focused != null) return [focused];
    final start = page * layoutSize;
    final end = (start + layoutSize).clamp(0, order.length);
    return order.sublist(start.clamp(0, order.length), end);
  }

  int get crossAxisCount => gridSize == 1 ? 1 : gridSize <= 4 ? 2 : 3;

  int get rowCount =>
      (visibleChannels.length / crossAxisCount).ceil().clamp(1, gridSize);

  GridState copyWith({
    int? layoutSize,
    int? page,
    int? channelCount,
    List<int>? order,
    int? focusedChannel,
    bool clearFocus = false,
    bool? singleHd,
  }) =>
      GridState(
        layoutSize: layoutSize ?? this.layoutSize,
        page: page ?? this.page,
        channelCount: channelCount ?? this.channelCount,
        order: order ?? this.order,
        focusedChannel:
            clearFocus ? null : (focusedChannel ?? this.focusedChannel),
        singleHd: singleHd ?? this.singleHd,
      );

  @override
  List<Object?> get props => [
        layoutSize,
        page,
        channelCount,
        order,
        focusedChannel,
        singleHd,
      ];
}

class GridCubit extends Cubit<GridState> {
  final ProfileStore _store;
  final String _profileId;
  final Future<void> Function(List<int> order)? _saveOrderOverride;

  /// True once the user has reordered; late [restore] must not clobber it.
  bool _userReordered = false;

  /// True once the user picked a layout; late [restore] must not clobber it.
  bool _userSetLayout = false;

  GridCubit({
    required ProfileStore store,
    required String profileId,
    int gridSize = 4,
    int channelCount = 4,
    List<int>? order,
    Future<void> Function(List<int> order)? saveOrder,
  // ignore: prefer_initializing_formals (private fields can't use `this.` with external named callers)
  })  : _store = store,
        // ignore: prefer_initializing_formals
        _profileId = profileId,
        _saveOrderOverride = saveOrder,
        super(GridState(
          layoutSize: gridSize,
          channelCount: channelCount,
          order: order ?? [for (var c = 1; c <= channelCount; c++) c],
        ));

  /// Restores the persisted channel order + layout for this profile.
  /// Call once after creation. Missing/invalid data leaves defaults;
  /// storage errors are ignored so the live view always opens.
  Future<void> restore() async {
    List<int>? saved;
    int? size;
    try {
      saved = await _store.loadChannelOrder(_profileId, state.channelCount);
      size = await _store.loadGridSize();
    } catch (_) {
      return;
    }
    if (isClosed) return;
    var next = state;
    // A reorder that landed while storage was still reading wins.
    if (saved != null && !_userReordered) {
      next = next.copyWith(order: saved, page: 0);
    }
    if (size == 1 || size == 4 || size == 9) {
      if (!_userSetLayout) next = next.copyWith(layoutSize: size);
    }
    if (next != state) emit(next);
  }

  void setGridSize(int size) {
    assert(size == 1 || size == 4 || size == 9);
    _userSetLayout = true;
    // An explicit layout pick always leaves single-camera focus.
    emit(state.copyWith(layoutSize: size, page: 0, clearFocus: true));
    unawaited(_persistGridSize(size));
  }

  /// Layout is global (not per profile like the channel order). Failures
  /// are swallowed: storage is absent in widget tests.
  Future<void> _persistGridSize(int size) async {
    try {
      await _store.saveGridSize(size);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Double-click / OK on a tile: show it alone (1x1), leaving the chosen
  /// [GridState.layoutSize] and [GridState.page] untouched.
  void focusChannel(int channel) {
    if (isClosed || state.focusedChannel == channel) return;
    if (!state.order.contains(channel)) return;
    emit(state.copyWith(focusedChannel: channel));
  }

  /// Leave the single-camera view; the saved layout + page are still there.
  void unfocus() {
    if (isClosed || !state.isFocused) return;
    emit(state.copyWith(clearFocus: true));
  }

  /// 1x1 tiles play HD by default; off forces the SD sub-stream.
  void setSingleHd(bool hd) {
    if (isClosed || state.singleHd == hd) return;
    emit(state.copyWith(singleHd: hd));
  }

  void nextPage() {
    if (state.isFocused) {
      final idx = state.order.indexOf(state.focusedChannel!);
      if (idx >= 0 && idx < state.order.length - 1) {
        emit(state.copyWith(focusedChannel: state.order[idx + 1]));
      }
      return;
    }
    if (state.page < state.pageCount - 1) {
      emit(state.copyWith(page: state.page + 1));
    }
  }

  void prevPage() {
    if (state.isFocused) {
      final idx = state.order.indexOf(state.focusedChannel!);
      if (idx > 0) {
        emit(state.copyWith(focusedChannel: state.order[idx - 1]));
      }
      return;
    }
    if (state.page > 0) emit(state.copyWith(page: state.page - 1));
  }

  /// Swaps two channels in the user order and persists it. A focused
  /// channel stays focused even when it moves to a different slot.
  Future<void> swapChannels(int a, int b) async {
    if (a == b || isClosed) return;
    _userReordered = true;
    final order = [...state.order];
    final ia = order.indexOf(a);
    final ib = order.indexOf(b);
    if (ia < 0 || ib < 0) return;
    order[ia] = b;
    order[ib] = a;
    emit(state.copyWith(order: order));
    try {
      if (_saveOrderOverride != null) {
        await _saveOrderOverride(order);
      } else {
        await _store.saveChannelOrder(_profileId, order);
      }
    } catch (_) {
      // Best-effort: the reorder is already visible in this session and
      // must not surface an unhandled async error from fire-and-forget UI
      // callers (e.g. a read-only/full prefs store).
    }
  }
}

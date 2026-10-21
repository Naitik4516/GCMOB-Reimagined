import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../profiles/data/profile_store.dart';

/// Grid layout: 1, 4, or 9 visible tiles + page index for >9 channels.
///
/// * [order] — user-arranged display order (persisted per profile). Tile
///   positions NEVER change on their own: a stream failing or recovering
///   leaves the slot exactly where the user put it.
/// * [spotlight] — a double-clicked/OK tile is shown alone (1x1, HD);
///   [returnSize]/[returnPage] restore the previous layout on exit.
/// * [singleHd] — 1x1 tiles play the HD main-stream (audio on); off to
///   force SD.
class GridState extends Equatable {
  final int gridSize;
  final int page;
  final int channelCount;
  final List<int> order;
  final bool spotlight;
  final int returnSize;
  final int returnPage;
  final bool singleHd;

  const GridState({
    this.gridSize = 4,
    this.page = 0,
    required this.channelCount,
    required this.order,
    this.spotlight = false,
    this.returnSize = 4,
    this.returnPage = 0,
    this.singleHd = true,
  });

  int get pageCount =>
      channelCount <= gridSize ? 1 : (channelCount / gridSize).ceil();

  /// 1-based channels visible on the current page.
  List<int> get visibleChannels {
    final start = page * gridSize;
    final end = (start + gridSize).clamp(0, order.length);
    return order.sublist(start.clamp(0, order.length), end);
  }

  int get crossAxisCount => gridSize == 1 ? 1 : gridSize <= 4 ? 2 : 3;

  int get rowCount =>
      (visibleChannels.length / crossAxisCount).ceil().clamp(1, gridSize);

  GridState copyWith({
    int? gridSize,
    int? page,
    int? channelCount,
    List<int>? order,
    bool? spotlight,
    int? returnSize,
    int? returnPage,
    bool? singleHd,
  }) =>
      GridState(
        gridSize: gridSize ?? this.gridSize,
        page: page ?? this.page,
        channelCount: channelCount ?? this.channelCount,
        order: order ?? this.order,
        spotlight: spotlight ?? this.spotlight,
        returnSize: returnSize ?? this.returnSize,
        returnPage: returnPage ?? this.returnPage,
        singleHd: singleHd ?? this.singleHd,
      );

  @override
  List<Object?> get props => [
        gridSize,
        page,
        channelCount,
        order,
        spotlight,
        returnSize,
        returnPage,
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
          gridSize: gridSize,
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
      if (!_userSetLayout) next = next.copyWith(gridSize: size);
    }
    if (next != state) emit(next);
  }

  void setGridSize(int size) {
    assert(size == 1 || size == 4 || size == 9);
    _userSetLayout = true;
    // An explicit layout pick always leaves spotlight mode.
    emit(state.copyWith(gridSize: size, page: 0, spotlight: false));
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

  /// Double-click / OK on a tile: show it alone (1x1), remembering the
  /// layout + page to restore on exit.
  void focusChannel(int channel) {
    if (isClosed) return;
    final idx = state.order.indexOf(channel);
    if (idx < 0) return;
    emit(state.copyWith(
      gridSize: 1,
      page: idx,
      spotlight: true,
      returnSize: state.spotlight ? state.returnSize : state.gridSize,
      returnPage: state.spotlight ? state.returnPage : state.page,
    ));
  }

  /// Leave the single-camera view, restoring the previous layout + page.
  void unfocus() {
    if (isClosed || !state.spotlight) return;
    final pages = state.channelCount <= state.returnSize
        ? 1
        : (state.channelCount / state.returnSize).ceil();
    emit(state.copyWith(
      gridSize: state.returnSize,
      page: state.returnPage.clamp(0, pages - 1),
      spotlight: false,
    ));
  }

  /// 1x1 tiles play HD by default; off forces the SD sub-stream.
  void setSingleHd(bool hd) {
    if (isClosed || state.singleHd == hd) return;
    emit(state.copyWith(singleHd: hd));
  }

  void nextPage() {
    if (state.page < state.pageCount - 1) {
      emit(state.copyWith(page: state.page + 1));
    }
  }

  void prevPage() {
    if (state.page > 0) emit(state.copyWith(page: state.page - 1));
  }

  /// Swaps two channels in the user order and persists it.
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
    if (_saveOrderOverride != null) {
      await _saveOrderOverride(order);
    } else {
      await _store.saveChannelOrder(_profileId, order);
    }
  }
}

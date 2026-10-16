import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../profiles/data/profile_store.dart';

/// Grid layout: 1, 4, or 9 visible tiles + page index for >9 channels.
///
/// * [order] — user-arranged display order (persisted per profile).
/// * [sunk] — channels that failed this session, shown after all working
///   tiles, in order of failure. Session-only, never persisted.
/// * [spotlight] — a double-clicked/OK tile is shown alone (1x1, HD);
///   [returnSize]/[returnPage] restore the previous layout on exit.
/// * [singleHd] — 1x1 tiles play the HD main-stream (audio on); off to
///   force SD.
class GridState extends Equatable {
  final int gridSize;
  final int page;
  final int channelCount;
  final List<int> order;
  final List<int> sunk;
  final bool spotlight;
  final int returnSize;
  final int returnPage;
  final bool singleHd;

  const GridState({
    this.gridSize = 4,
    this.page = 0,
    required this.channelCount,
    required this.order,
    this.sunk = const [],
    this.spotlight = false,
    this.returnSize = 4,
    this.returnPage = 0,
    this.singleHd = true,
  });

  /// Working tiles first (in user order), failed tiles last.
  List<int> get effectiveOrder => [
        for (final c in order)
          if (!sunk.contains(c)) c,
        for (final c in sunk)
          if (order.contains(c)) c,
      ];

  int get pageCount =>
      channelCount <= gridSize ? 1 : (channelCount / gridSize).ceil();

  /// 1-based channels visible on the current page.
  List<int> get visibleChannels {
    final eff = effectiveOrder;
    final start = page * gridSize;
    final end = (start + gridSize).clamp(0, eff.length);
    return eff.sublist(start.clamp(0, eff.length), end);
  }

  int get crossAxisCount => gridSize == 1 ? 1 : gridSize <= 4 ? 2 : 3;

  int get rowCount =>
      (visibleChannels.length / crossAxisCount).ceil().clamp(1, gridSize);

  GridState copyWith({
    int? gridSize,
    int? page,
    int? channelCount,
    List<int>? order,
    List<int>? sunk,
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
        sunk: sunk ?? this.sunk,
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
        sunk,
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

  /// Loads persisted user order (if any). Call once after creation.
  Future<void> loadOrder() async {
    final saved = await _store.loadChannelOrder(_profileId, state.channelCount);
    if (!isClosed && saved != null) {
      emit(state.copyWith(order: saved, page: 0));
    }
  }

  void setGridSize(int size) {
    assert(size == 1 || size == 4 || size == 9);
    // An explicit layout pick always leaves spotlight mode.
    emit(state.copyWith(gridSize: size, page: 0, spotlight: false));
  }

  /// Double-click / OK on a tile: show it alone (1x1), remembering the
  /// layout + page to restore on exit.
  void focusChannel(int channel) {
    if (isClosed) return;
    final idx = state.effectiveOrder.indexOf(channel);
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

  /// Sinks a failed channel behind all working tiles. No retry is
  /// attempted afterwards — recovery is strictly user-initiated.
  void markFailed(int channel) {
    if (isClosed || state.sunk.contains(channel)) return;
    emit(state.copyWith(sunk: [...state.sunk, channel]));
  }

  /// Lifts a channel back into user order after a successful manual retry.
  void markRecovered(int channel) {
    if (isClosed || !state.sunk.contains(channel)) return;
    emit(state.copyWith(
        sunk: state.sunk.where((c) => c != channel).toList()));
  }
}

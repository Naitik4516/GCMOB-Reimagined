import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../profiles/data/profile_store.dart';

/// Grid layout: 1, 4, or 9 visible tiles + page index for >9 channels.
///
/// * [order] — user-arranged display order (persisted per profile).
/// * [sunk] — channels that failed this session, shown after all working
///   tiles, in order of failure. Session-only, never persisted.
class GridState extends Equatable {
  final int gridSize;
  final int page;
  final int channelCount;
  final List<int> order;
  final List<int> sunk;

  const GridState({
    this.gridSize = 4,
    this.page = 0,
    required this.channelCount,
    required this.order,
    this.sunk = const [],
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
  }) =>
      GridState(
        gridSize: gridSize ?? this.gridSize,
        page: page ?? this.page,
        channelCount: channelCount ?? this.channelCount,
        order: order ?? this.order,
        sunk: sunk ?? this.sunk,
      );

  @override
  List<Object?> get props => [gridSize, page, channelCount, order, sunk];
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
    emit(state.copyWith(gridSize: size, page: 0));
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

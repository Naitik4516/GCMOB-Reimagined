import 'dart:async';

import 'package:gcmob_reimagined/features/profiles/data/profile_store.dart';

/// In-memory grid persistence with optional read gates.
///
/// Complete [orderGate] / [sizeGate] to release a `restore()` that is
/// deliberately parked mid-read in race tests.
class FakeGridStore extends ProfileStore {
  FakeGridStore({this.order, this.size = 4});

  List<int>? order;
  int size;

  Completer<void>? orderGate;
  Completer<void>? sizeGate;

  List<int>? savedOrder;
  int? savedSize;

  @override
  Future<List<int>?> loadChannelOrder(String profileId, int channelCount) async {
    await orderGate?.future;
    return order == null ? null : List.of(order!);
  }

  @override
  Future<void> saveChannelOrder(String profileId, List<int> order) async {
    savedOrder = List.of(order);
  }

  @override
  Future<int> loadGridSize() async {
    await sizeGate?.future;
    return size;
  }

  @override
  Future<void> saveGridSize(int size) async {
    savedSize = size;
  }
}

import 'package:gcmob_reimagined/features/live/bloc/grid_cubit.dart';
import 'package:gcmob_reimagined/features/profiles/data/profile_store.dart';

/// GridCubit with no-op persistence, shared by the widget test suites.
///
/// Tests that exercise [GridCubit.restore] must call
/// `SharedPreferences.setMockInitialValues({...})` first; otherwise the plugin
/// is missing under `flutter test`.
GridCubit testGrid({
  int gridSize = 9,
  int channelCount = 16,
  List<int>? order,
  List<List<int>>? saved,
}) {
  return GridCubit(
    store: ProfileStore(),
    profileId: 'test',
    gridSize: gridSize,
    channelCount: channelCount,
    order: order,
    saveOrder: (o) async => saved?.add(o),
  );
}

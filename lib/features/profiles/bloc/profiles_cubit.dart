import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/profile_store.dart';
import '../models/dvr_profile.dart';

enum ProfilesStatus { loading, loaded, error }

class ProfilesState extends Equatable {
  final ProfilesStatus status;
  final List<DvrProfile> profiles;
  final String? error;

  const ProfilesState({
    this.status = ProfilesStatus.loading,
    this.profiles = const [],
    this.error,
  });

  ProfilesState copyWith({
    ProfilesStatus? status,
    List<DvrProfile>? profiles,
    String? error,
  }) =>
      ProfilesState(
        status: status ?? this.status,
        profiles: profiles ?? this.profiles,
        error: error,
      );

  @override
  List<Object?> get props => [status, profiles, error];
}

class ProfilesCubit extends Cubit<ProfilesState> {
  final ProfileStore _store;
  ProfilesCubit(this._store) : super(const ProfilesState());

  Future<void> load() async {
    emit(state.copyWith(status: ProfilesStatus.loading));
    try {
      final profiles = await _store.loadProfiles();
      emit(state.copyWith(status: ProfilesStatus.loaded, profiles: profiles));
    } catch (e) {
      emit(state.copyWith(status: ProfilesStatus.error, error: '$e'));
    }
  }

  Future<void> save(DvrProfile profile, String password) async {
    await _store.upsertProfile(profile, password);
    await load();
  }

  Future<void> remove(String id) async {
    await _store.deleteProfile(id);
    await load();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../live/ui/live_page.dart';
import '../bloc/profiles_cubit.dart';
import '../data/profile_store.dart';
import 'profile_form_page.dart';

/// Entry screen: list of DVR profiles. First item autofocused for TV D-Pad.
class ProfileListPage extends StatefulWidget {
  const ProfileListPage({super.key});

  @override
  State<ProfileListPage> createState() => _ProfileListPageState();
}

class _ProfileListPageState extends State<ProfileListPage> {
  final _store = ProfileStore();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProfilesCubit(_store)..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('CCTV — DVR Profiles')),
        body: BlocBuilder<ProfilesCubit, ProfilesState>(
          builder: (context, state) {
            if (state.status == ProfilesStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == ProfilesStatus.error) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load: ${state.error}'),
                    ElevatedButton(
                      onPressed: () => context.read<ProfilesCubit>().load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            if (state.profiles.isEmpty) {
              return const Center(
                child: Text(
                  'No DVR configured.\nAdd one with the + button.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            return ListView.builder(
              itemCount: state.profiles.length,
              itemBuilder: (context, i) {
                final p = state.profiles[i];
                return ListTile(
                  autofocus: i == 0,
                  leading: const Icon(Icons.dns),
                  title: Text(p.name),
                  subtitle: Text(
                      '${p.host}:${p.rtspPort} • ${p.username} • ${p.channelCount}ch'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        context.read<ProfilesCubit>().remove(p.id),
                  ),
                  onTap: () async {
                    final pass = await _store.loadPassword(p.id);
                    if (!context.mounted) return;
                    if (pass == null || pass.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'No password stored — edit profile to re-enter.')),
                      );
                      return;
                    }
                    await _store.saveLastProfile(p.id);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LivePage(profile: p, password: pass),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: Builder(
          builder: (fabContext) => FloatingActionButton(
            onPressed: () {
              Navigator.of(fabContext).push(
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: fabContext.read<ProfilesCubit>(),
                    child: const ProfileFormPage(),
                  ),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

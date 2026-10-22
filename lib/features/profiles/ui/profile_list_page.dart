import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../live/ui/live_page.dart';
import '../bloc/profiles_cubit.dart';
import '../data/profile_store.dart';
import '../models/dvr_profile.dart';
import '../../../app/adaptive_shell.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import 'profile_form_page.dart';

/// Entry screen: list of DVR profiles. First item autofocused for TV D-Pad.
class ProfileListPage extends StatefulWidget {
  const ProfileListPage({super.key});

  @override
  State<ProfileListPage> createState() => _ProfileListPageState();
}

class _ProfileListPageState extends State<ProfileListPage> {
  final _store = ProfileStore();
  // Owned by the State, not created inside build(): this context is an
  // ancestor of the BlocProvider, so `context.read` from here (sheet
  // callbacks, dialogs) would not resolve it. Callers use `_cubit` directly.
  late final ProfilesCubit _cubit = ProfilesCubit(_store)..load();
  bool _opening = false;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _openProfile(DvrProfile p) async {
    if (_opening) return;
    _opening = true;
    try {
      String? pass;
      try {
        pass = await _store.loadPassword(p.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Couldn\'t read the stored password — is a system keyring available?',
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      if (pass == null || pass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No password stored — edit profile to re-enter.')),
        );
        return;
      }
      try {
        await _store.saveLastProfile(p.id);
      } catch (_) {
        // A missing "last profile" hint must not block opening live view.
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        CctvPageRoute(
          builder: (_) => LivePage(profile: p, password: pass!),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  void _showActions(DvrProfile p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Open live view'),
              autofocus: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openProfile(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  CctvPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: _cubit,
                      child: ProfileFormPage(existing: p),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(p);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(DvrProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Remove "${p.name}"? The stored password is deleted too.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await _cubit.remove(p.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted "${p.name}"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\'t delete: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocProvider.value(
      value: _cubit,
      child: AdaptiveShell(
        title: 'DVR Profiles',
        actions: [
          BlocBuilder<ProfilesCubit, ProfilesState>(
            builder: (context, state) {
              if (state.profiles.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${state.profiles.length}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        body: BlocBuilder<ProfilesCubit, ProfilesState>(
          builder: (context, state) {
            return AnimatedSwitcher(
              duration: CctvTheme.durMed,
              switchInCurve: CctvTheme.curveEmphasized,
              child: _bodyFor(context, state),
            );
          },
        ),
        floatingActionButton: _FocusOutlineFab(
          onPressed: () {
            Navigator.of(context).push(
              CctvPageRoute(
                builder: (_) => BlocProvider.value(
                  value: _cubit,
                  child: const ProfileFormPage(),
                ),
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Add DVR'),
        ),
      ),
    );
  }

  Widget _bodyFor(BuildContext context, ProfilesState state) {
    switch (state.status) {
      case ProfilesStatus.loading:
        return _skeleton(context);
      case ProfilesStatus.error:
        return _errorState(context, state);
      case ProfilesStatus.loaded:
        if (state.profiles.isEmpty) return _emptyState(context);
        return _profileList(context, state);
    }
  }

  Widget _skeleton(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('loading'),
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => const Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(Icons.dns)),
          title: Text('Loading…'),
          subtitle: LinearProgressIndicator(),
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context, ProfilesState state) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    color: scheme.error, size: 40),
                const SizedBox(height: 12),
                Text('Failed to load: ${state.error}'),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      context.read<ProfilesCubit>().load(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.video_library_outlined,
                  size: 40, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(
              'No DVR yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first Dahua / CP Plus recorder to start watching live cameras.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileList(BuildContext context, ProfilesState state) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      key: const ValueKey('list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: state.profiles.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final p = state.profiles[i];
        return _ProfileCard(
          profile: p,
          autofocus: i == 0,
          accent: scheme.primary,
          onOpen: () => _openProfile(p),
          onMore: () => _showActions(p),
        );
      },
    );
  }
}

/// "Add DVR" FAB with the shared amber focus outline, so D-Pad users can see
/// which control owns focus on TV. Material's default focus overlay is too
/// faint over the FAB's primary container colour.
class _FocusOutlineFab extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;

  const _FocusOutlineFab({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  State<_FocusOutlineFab> createState() => _FocusOutlineFabState();
}

class _FocusOutlineFabState extends State<_FocusOutlineFab> {
  final _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() => _focused = _node.hasFocus);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same radius as floatingActionButtonTheme in CctvTheme.dark().
    const radius = BorderRadius.all(Radius.circular(16));
    return FloatingActionButton.extended(
      focusNode: _node,
      onPressed: widget.onPressed,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: _focused ? CctvTheme.focusColor : Colors.transparent,
          width: _focused ? 2 : 1,
        ),
      ),
      icon: widget.icon,
      label: widget.label,
    );
  }
}

class _ProfileCard extends StatefulWidget {
  final DvrProfile profile;
  final bool autofocus;
  final Color accent;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  const _ProfileCard({
    required this.profile,
    required this.autofocus,
    required this.accent,
    required this.onOpen,
    required this.onMore,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _focused = false;
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() => _focused = _node.hasFocus);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _focused ? CctvTheme.focusScale : 1.0,
      duration: CctvTheme.durShort,
      curve: CctvTheme.curveEmphasized,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _focused ? CctvTheme.focusColor : Colors.white10,
            width: _focused ? 2 : 1,
          ),
        ),
        child: ListTile(
          autofocus: widget.autofocus,
          focusNode: _node,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.dns),
          ),
          title: Text(widget.profile.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${widget.profile.host}:${widget.profile.rtspPort} • '
            '${widget.profile.username} • '
            '${widget.profile.channelCount}ch',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Profile actions',
            onPressed: widget.onMore,
          ),
          onTap: () {
            _node.requestFocus();
            widget.onOpen();
          },
          onLongPress: widget.onMore,
        ),
      ),
    );
  }
}

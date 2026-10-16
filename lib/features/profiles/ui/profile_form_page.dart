import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/adaptive_shell.dart';
import '../../../app/theme.dart';
import '../bloc/profiles_cubit.dart';
import '../data/profile_store.dart';
import '../models/dvr_profile.dart';

/// Add / edit a DVR profile. Password field is never pre-filled from storage.
class ProfileFormPage extends StatefulWidget {
  final DvrProfile? existing;
  const ProfileFormPage({super.key, this.existing});

  @override
  State<ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends State<ProfileFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  int _channels = 8;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '192.168.1.240');
    _port = TextEditingController(text: '${e?.rtspPort ?? 554}');
    _user = TextEditingController(text: e?.username ?? 'admin');
    _pass = TextEditingController();
    _channels = e?.channelCount ?? 8;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final cubit = context.read<ProfilesCubit>();
      final id = widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final profile = DvrProfile(
        id: id,
        name: _name.text.trim(),
        host: _host.text.trim(),
        rtspPort: int.parse(_port.text.trim()),
        username: _user.text.trim(),
        channelCount: _channels,
      );
      // Editing without re-entering password keeps the stored one.
      var password = _pass.text;
      if (widget.existing != null && password.isEmpty) {
        password = await ProfileStore().loadPassword(id) ?? '';
      }
      await cubit.save(profile, password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "${profile.name}"')),
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AdaptiveShell(
      title: isEdit ? 'Edit DVR' : 'Add DVR',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _SectionCard(
              title: 'Display',
              icon: Icons.label_outline,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Profile Name',
                      hintText: 'Home NVR',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total Channels',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 4, label: Text('4')),
                      ButtonSegment(value: 8, label: Text('8')),
                      ButtonSegment(value: 16, label: Text('16')),
                    ],
                    selected: {_channels},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _channels = s.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Connection',
              icon: Icons.lan_outlined,
              child: Column(
                children: [
                  TextFormField(
                    controller: _host,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'DVR IP / Hostname',
                      hintText: '192.168.1.240',
                      prefixIcon: Icon(Icons.computer_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _port,
                    decoration: const InputDecoration(
                      labelText: 'RTSP Port (default 554)',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n < 1 || n > 65535) return '1–65535';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _user,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: isEdit
                          ? 'Password (re-enter to update)'
                          : 'Password',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: AnimatedSwitcher(
                          duration: CctvTheme.durShort,
                          child: Icon(
                            _obscure
                                ? Icons.visibility
                                : Icons.visibility_off,
                            key: ValueKey(_obscure),
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (isEdit && (v == null || v.isEmpty)) {
                        return null; // keep stored password
                      }
                      return (v == null || v.isEmpty) ? 'Required' : null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

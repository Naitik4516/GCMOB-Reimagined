import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    if (!_formKey.currentState!.validate()) return;
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
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.existing == null ? 'Add DVR' : 'Edit DVR')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Profile Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(
                  labelText: 'DVR IP / Hostname',
                  hintText: '192.168.1.240'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _port,
              decoration:
                  const InputDecoration(labelText: 'RTSP Port (default 554)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n < 1 || n > 65535) return '1–65535';
                return null;
              },
            ),
            TextFormField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: widget.existing == null
                    ? 'Password'
                    : 'Password (re-enter to update)',
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (widget.existing != null &&
                    (v == null || v.isEmpty)) {
                  return null; // keep stored password
                }
                return (v == null || v.isEmpty) ? 'Required' : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _channels,
              decoration:
                  const InputDecoration(labelText: 'Total Channels'),
              items: const [4, 8, 16]
                  .map((c) => DropdownMenuItem(
                      value: c, child: Text('$c channels')))
                  .toList(),
              onChanged: (v) => setState(() => _channels = v ?? 8),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

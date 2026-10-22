import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/adaptive_shell.dart';
import '../../../app/theme.dart';
import '../../../core/rtsp/rtsp_probe.dart';
import '../../../core/rtsp/rtsp_url.dart';
import '../bloc/profiles_cubit.dart';
import '../data/profile_store.dart';
import '../models/dvr_profile.dart';

/// Add / edit a DVR profile. Password field is never pre-filled from storage.
///
/// Saving runs an RTSP handshake first: creation always tests the connection,
/// editing does it whenever host/port/username/password changed. A failed
/// test blocks the save behind a "Save anyway" confirmation.
class ProfileFormPage extends StatefulWidget {
  final DvrProfile? existing;
  final RtspProbe probe;

  /// Storage override for tests; defaults to the real keyring-backed store.
  final ProfileStore? store;

  const ProfileFormPage({
    super.key,
    this.existing,
    this.probe = const RtspProbe(),
    this.store,
  });

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
  final _passFocus = FocusNode();
  late final ProfileStore _store = widget.store ?? ProfileStore();
  int _channels = 8;
  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;
  String? _passwordError;
  String? _probeError;
  bool _probeOk = false;

  bool get _busy => _testing || _saving;

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
    _passFocus.dispose();
    super.dispose();
  }

  /// Clears a previous test result as soon as the connection details change,
  /// so a stale "Connected" can never vouch for a different host or password.
  void _invalidateProbe() {
    if (_probeError == null && !_probeOk) return;
    setState(() {
      _probeError = null;
      _probeOk = false;
    });
  }

  /// Creation always probes. Editing only probes when something that affects
  /// the handshake changed — renaming a profile must work while the DVR is
  /// offline.
  bool _shouldProbe(DvrProfile profile, {required bool passwordEntered}) {
    final existing = widget.existing;
    if (existing == null) return true;
    return passwordEntered ||
        existing.host != profile.host ||
        existing.rtspPort != profile.rtspPort ||
        existing.username != profile.username;
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    final cubit = context.read<ProfilesCubit>();
    final isEdit = widget.existing != null;
    final id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final profile = DvrProfile(
      id: id,
      name: _name.text.trim(),
      host: normalizeRtspHost(_host.text),
      rtspPort: int.parse(_port.text.trim()),
      username: _user.text.trim(),
      channelCount: _channels,
    );

    setState(() => _passwordError = null);

    // Editing without re-entering password keeps the stored one.
    var password = _pass.text;
    if (isEdit && password.isEmpty) {
      try {
        password = await _store.loadPassword(id) ?? '';
      } catch (_) {
        password = '';
      }
      if (!mounted) return;
      if (password.isEmpty) {
        setState(() {
          _passwordError = 'Stored password unavailable — re-enter it';
        });
        _passFocus.requestFocus();
        return;
      }
    }

    if (_shouldProbe(profile, passwordEntered: _pass.text.isNotEmpty)) {
      setState(() {
        _testing = true;
        _probeError = null;
        _probeOk = false;
      });
      RtspProbeResult result;
      try {
        result = await widget.probe.probe(
          host: profile.host,
          port: profile.rtspPort,
          user: profile.username,
          password: password,
        );
      } catch (e) {
        result = RtspProbeResult(
          RtspProbeStatus.badResponse,
          'Connection test failed: $e',
        );
      }
      if (!mounted) return;
      setState(() => _testing = false);
      if (!result.ok) {
        setState(() => _probeError = result.message);
        final saveAnyway = await _askSaveAnyway(result.message);
        if (!mounted || saveAnyway != true) return;
      } else {
        setState(() => _probeOk = true);
      }
    }

    setState(() => _saving = true);
    final verified = _probeOk;
    try {
      await cubit.save(profile, password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verified
                ? 'Connected — saved "${profile.name}"'
                : 'Saved "${profile.name}"'),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _askSaveAnyway(String message) {
    return showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Connection failed'),
        content: Text('$message\n\nSave this profile anyway?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Fix it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  Widget _probeStatus(ColorScheme scheme) {
    if (_testing) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Testing connection…'),
          ],
        ),
      );
    }
    final color = _probeOk ? Colors.greenAccent : scheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(
            _probeOk ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _probeOk ? 'Connection verified' : _probeError ?? '',
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
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
                    readOnly: _busy,
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
                    onSelectionChanged: _busy
                        ? null
                        : (s) => setState(() => _channels = s.first),
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
                    readOnly: _busy,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _invalidateProbe(),
                    decoration: const InputDecoration(
                      labelText: 'DVR IP / Hostname',
                      hintText: '192.168.1.240',
                      prefixIcon: Icon(Icons.computer_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      try {
                        normalizeRtspHost(v);
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _port,
                    readOnly: _busy,
                    onChanged: (_) => _invalidateProbe(),
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
                    readOnly: _busy,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _invalidateProbe(),
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
                    focusNode: _passFocus,
                    readOnly: _busy,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                      _invalidateProbe();
                    },
                    decoration: InputDecoration(
                      labelText: isEdit
                          ? 'Password (re-enter to update)'
                          : 'Password',
                      errorText: _passwordError,
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
            if (_testing || _probeError != null || _probeOk)
              _probeStatus(Theme.of(context).colorScheme),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_testing
                  ? 'Testing connection…'
                  : _saving
                      ? 'Saving…'
                      : 'Save'),
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

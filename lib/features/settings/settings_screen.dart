import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../design_system/design_system.dart';

/// The Preference Center: how far Nearby reaches, the Dating Lens, discretion, what the person has consented
/// to (each purpose can be withdrawn here, and withdrawing deletes that data), signed-in devices, their data,
/// and the Grievance Officer. Every switch takes effect at once and snaps back if the server refuses.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Preferences? _prefs;
  List<ConsentPurpose> _consents = const [];
  List<DeviceSession> _sessions = const [];
  OfficerContact? _officer;
  double? _radius; // while the slider is being dragged
  String? _loadError;
  bool _busy = false;

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final prefs = await _repo.preferences();
      final consents = await _repo.consents();
      final sessions = await _repo.sessions();
      OfficerContact? officer;
      try {
        officer = await _repo.officer();
      } catch (_) {
        officer = null; // not published yet: the section is simply left out
      }
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _consents = consents;
        _sessions = sessions;
        _officer = officer;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = _message(e));
    }
  }

  String _message(Object e) => e is ApiError
      ? e.detail
      : 'Couldn\'t reach OneDay. Check your connection and try again.';

  void _say(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  /// Shows [optimistic] at once, then the server's answer; on failure the old value comes back.
  Future<void> _change(
    Preferences optimistic,
    Future<Preferences> Function() save,
  ) async {
    final before = _prefs;
    setState(() {
      _prefs = optimistic;
      _radius = null;
    });
    try {
      final saved = await save();
      if (mounted) setState(() => _prefs = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = before);
      _say(_message(e));
    }
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _say(_message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _toggleConsent(ConsentPurpose purpose, bool on) async {
    if (!on) {
      final sure = await _confirm(
        title: 'Withdraw "${purpose.title}"?',
        body: purpose.onWithdrawal,
        action: 'Withdraw',
      );
      if (!sure || !mounted) return;
    }
    await _guarded(() async {
      final consents = on
          ? await _repo.grant(purpose.purpose)
          : await _repo.withdraw(purpose.purpose);
      // Withdrawing can change preferences too (the Dating Lens turns off with its consent).
      final prefs = await _repo.preferences();
      if (!mounted) return;
      setState(() {
        _consents = consents;
        _prefs = prefs;
      });
      if (purpose.purpose == 'LOCATION_DISCOVERY') {
        ref.invalidate(nearbyMomentsProvider);
      }
    });
  }

  Future<void> _pauseLocation() => _guarded(() async {
    await _repo.pauseLocation();
    ref.invalidate(nearbyMomentsProvider);
    if (mounted) _say('Your area is no longer shared.');
  });

  Future<void> _endSession(DeviceSession session) => _guarded(() async {
    await _repo.endSession(session.id);
    final sessions = await _repo.sessions();
    if (mounted) setState(() => _sessions = sessions);
  });

  Future<void> _export() => _guarded(() async {
    final data = await _repo.exportData();
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)),
    );
    if (mounted) {
      _say('Your data (${data.length} sections) is copied to the clipboard.');
    }
  });

  Future<void> _deleteAccount() async {
    final typed = TextEditingController();
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your profile, stories, chats and connections are erased. This can\'t be undone. '
              'Type DELETE to confirm.',
            ),
            const SizedBox(height: OdSpace.x1_5),
            TextField(
              controller: typed,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'DELETE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep my account'),
          ),
          ListenableBuilder(
            listenable: typed,
            builder: (_, _) => TextButton(
              onPressed: typed.text.trim() == 'DELETE'
                  ? () => Navigator.of(dialog).pop(true)
                  : null,
              child: const Text('Delete forever'),
            ),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _guarded(() async {
      await _repo.deleteAccount();
      // The session is gone with the account; the router returns to Welcome.
      await ref.read(authControllerProvider.notifier).signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: prefs == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : OdClosureCard(
                      icon: Icons.wifi_off_rounded,
                      title: 'Couldn\'t load your settings',
                      message: _loadError!,
                      actionLabel: 'Try again',
                      onAction: _load,
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                OdSpace.gutter,
                OdSpace.x1,
                OdSpace.gutter,
                OdSpace.x6,
              ),
              children: _sections(context, prefs),
            ),
    );
  }

  List<Widget> _sections(BuildContext context, Preferences prefs) {
    final c = context.od;
    final radius = (_radius ?? prefs.discoveryRadiusKm.toDouble()).clamp(
      Preferences.minRadiusKm.toDouble(),
      Preferences.maxRadiusKm.toDouble(),
    );
    return [
      const _Header('Discovery'),
      Text(
        'Nearby reaches ${radius.round()} km',
        style: context.type.titleMedium,
      ),
      Slider(
        value: radius,
        min: Preferences.minRadiusKm.toDouble(),
        max: Preferences.maxRadiusKm.toDouble(),
        divisions: Preferences.maxRadiusKm - Preferences.minRadiusKm,
        label: '${radius.round()} km',
        semanticFormatterCallback: (v) => '${v.round()} kilometres',
        onChanged: (v) => setState(() => _radius = v),
        onChangeEnd: (v) => _change(
          prefs.copyWith(discoveryRadiusKm: v.round()),
          () => _repo.update(discoveryRadiusKm: v.round()),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Dating Lens'),
        subtitle: const Text(
          'Open to dating. Only people who also turned it on can tell.',
        ),
        value: prefs.datingLens,
        onChanged: (on) => _change(
          prefs.copyWith(datingLens: on),
          () => _repo.update(datingLens: on),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Private account'),
        subtitle: const Text(
          'Only Connections see your profile. You can still share stories nearby.',
        ),
        value: prefs.privateAccount,
        onChanged: (on) => _change(
          prefs.copyWith(privateAccount: on),
          () => _repo.update(privateAccount: on),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Discretion Mode'),
        subtitle: const Text(
          'Notifications say nothing about who or what on the lock screen.',
        ),
        value: prefs.discretionMode,
        onChanged: (on) => _change(
          prefs.copyWith(discretionMode: on),
          () => _repo.update(discretionMode: on),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.location_off_outlined, color: c.textSecondary),
        title: const Text('Stop sharing my area'),
        subtitle: const Text(
          'You leave Nearby and the map until you share it again.',
        ),
        onTap: _busy ? null : _pauseLocation,
      ),
      const _Header('Your consent'),
      Text(
        'Each purpose is separate. Withdrawing one deletes that data straight away.',
        style: context.type.bodyMedium,
      ),
      for (final purpose in _consents)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(purpose.title),
          subtitle: Text(purpose.processes),
          value: purpose.granted,
          onChanged: _busy ? null : (on) => _toggleConsent(purpose, on),
        ),
      const _Header('Signed-in devices'),
      for (final session in _sessions)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.phone_android_rounded, color: c.textSecondary),
          title: Text(session.device),
          subtitle: session.current ? const Text('This device') : null,
          trailing: session.current
              ? null
              : TextButton(
                  onPressed: _busy ? null : () => _endSession(session),
                  child: const Text('Sign out'),
                ),
        ),
      const _Header('Your data'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.download_rounded, color: c.textSecondary),
        title: const Text('Copy my data'),
        subtitle: const Text('Everything OneDay holds about you, as JSON.'),
        onTap: _busy ? null : _export,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.delete_forever_rounded, color: c.danger),
        title: Text('Delete my account', style: TextStyle(color: c.danger)),
        onTap: _busy ? null : _deleteAccount,
      ),
      if (_officer != null) ...[
        const _Header('Help and grievances'),
        Text(_officer!.name, style: context.type.titleMedium),
        SelectableText(_officer!.email, style: context.type.bodyLarge),
        if ((_officer!.address ?? '').isNotEmpty)
          Text(_officer!.address!, style: context.type.bodyMedium),
        if (prefs.emergencyNumber != null) ...[
          const SizedBox(height: OdSpace.x1),
          Text(
            'In an emergency, call ${prefs.emergencyNumber}.',
            style: context.type.bodyMedium,
          ),
        ],
      ],
      const SizedBox(height: OdSpace.x4),
      OdButton(
        label: 'Sign out',
        variant: OdButtonVariant.secondary,
        expand: true,
        onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: OdSpace.x4, bottom: OdSpace.x1),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: context.type.labelMedium?.copyWith(
          color: context.od.textTertiary,
          letterSpacing: 1,
        ),
      ),
    ),
  );
}

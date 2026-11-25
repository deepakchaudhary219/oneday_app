import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../../core/plans.dart' show whenLabel;
import '../../core/providers.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => e is ApiError
    ? e.detail
    : 'Couldn\'t reach OneDay. Check your connection and try again.';

/// Date Mode: a plan between two Connections with safety built in. Exact location is shared only if both
/// people turn it on, and only around the date; a trusted contact can follow along; "Going OK?" and SOS are one
/// tap; "Home safe" ends it. Nothing on this screen tells the other person about a check-in or an SOS.
class DatesScreen extends ConsumerStatefulWidget {
  const DatesScreen({super.key});

  @override
  ConsumerState<DatesScreen> createState() => _DatesScreenState();
}

class _DatesScreenState extends ConsumerState<DatesScreen> {
  List<DatePlan>? _dates;
  String? _loadError;
  bool _busy = false;
  Timer? _position;

  /// The server takes about one update a minute (it rate-limits faster ones).
  static const _every = Duration(seconds: 60);

  DatesRepository get _repo => ref.read(datesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _position?.cancel();
    super.dispose();
  }

  /// Sends this phone's position for a date that needs it, while this screen is open. Stops by itself when
  /// sharing stops, the window closes or the date ends.
  void _syncPosition() {
    final sharing = (_dates ?? const <DatePlan>[]).where((d) => d.shouldSend);
    if (sharing.isEmpty) {
      _position?.cancel();
      _position = null;
      return;
    }
    if (_position != null) return;
    _sendPosition();
    _position = Timer.periodic(_every, (_) => _sendPosition());
  }

  Future<void> _sendPosition() async {
    final date = (_dates ?? const <DatePlan>[]).where((d) => d.shouldSend).firstOrNull;
    if (date == null) return;
    final here = await ref.read(preciseLocationSourceProvider).current();
    if (here == null || !mounted) return;
    try {
      final updated = await _repo.sendPosition(date.id, here.lat, here.lon);
      if (!mounted) return;
      setState(
        () => _dates = [
          for (final d in _dates ?? const <DatePlan>[])
            d.id == updated.id ? updated : d,
        ],
      );
    } catch (_) {
      // Missed one: the next tick tries again.
    }
  }

  Future<void> _load() async {
    try {
      final dates = await _repo.list();
      if (!mounted) return;
      setState(() {
        _dates = dates;
        _loadError = null;
      });
      _syncPosition();
    } catch (e) {
      if (mounted) setState(() => _loadError = _problem(e));
    }
  }

  void _say(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  /// Runs an action that returns the date's new state and puts it in the list.
  Future<void> _change(Future<DatePlan> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await action();
      if (!mounted) return;
      setState(
        () => _dates = [
          for (final d in _dates ?? const <DatePlan>[])
            d.id == changed.id ? changed : d,
        ],
      );
      _syncPosition();
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reply(Future<SafetyReply> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final reply = await action();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(
            '${reply.message}\n\nEmergency: ${reply.emergencyNumber}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sos(DatePlan date) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Send an SOS?'),
        content: Text(
          'Our safety team and your trusted contact are alerted now. ${date.partner} is not told. '
          'If you are in danger, call ${date.emergencyNumber}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) await _reply(() => _repo.sos(date.id));
  }

  Future<void> _trustedContact(DatePlan date) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Trusted contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'They get a private link by text to follow this date. They don\'t need the app.',
            ),
            const SizedBox(height: OdSpace.x1_5),
            TextField(
              controller: name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Their name',
                counterText: '',
              ),
            ),
            const SizedBox(height: OdSpace.x1),
            TextField(
              controller: phone,
              maxLength: 24,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Their phone number',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save != true || !mounted || phone.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final texted = await _repo.setTrustedContact(
        date.id,
        phone: phone.text,
        name: name.text,
      );
      await _load();
      if (mounted) {
        _say(
          texted
              ? 'Saved. They\'ve been texted a private link.'
              : 'Saved. The text couldn\'t be sent just now.',
        );
      }
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _debrief(DatePlan date) async {
    final answers = await showOdSheet<Set<DebriefAnswer>>(
      context,
      builder: (_) => _DebriefSheet(partner: date.partner),
    );
    if (answers == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final said = await _repo.debrief(date.id, answers);
      await _load();
      if (mounted) _say(said);
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose() async {
    final created = await showOdSheet<DatePlan>(
      context,
      builder: (_) => const _ProposeSheet(),
    );
    if (created != null && mounted) {
      setState(() => _dates = [created, ...?_dates]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    // The partner's position arrives over the socket while both share.
    ref.listen(realtimeEventsProvider, (_, next) {
      if (next.value?.type == 'date-location') _load();
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dates'),
        actions: [
          TextButton(onPressed: _propose, child: const Text('Plan a date')),
          const SizedBox(width: OdSpace.x1),
        ],
      ),
      body: dates == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : Padding(
                      padding: const EdgeInsets.all(OdSpace.x3),
                      child: Text(_loadError!, textAlign: TextAlign.center),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                OdSpace.gutter,
                OdSpace.x1,
                OdSpace.gutter,
                OdSpace.x6,
              ),
              children: [
                if (dates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: OdSpace.x4),
                    child: Text(
                      'No dates yet. When you and a Connection are ready, plan one here.',
                      textAlign: TextAlign.center,
                      style: context.type.bodyLarge,
                    ),
                  ),
                for (final date in dates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: OdSpace.x2),
                    child: OdCard(child: _card(context, date)),
                  ),
              ],
            ),
    );
  }

  Widget _card(BuildContext context, DatePlan date) {
    final c = context.od;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('With ${date.partner}', style: context.type.titleLarge),
        const SizedBox(height: OdSpace.x0_5),
        Text(
          '${whenLabel(date.startsAt, now)} · ${date.place}',
          style: context.type.bodyLarge,
        ),
        const SizedBox(height: OdSpace.x1_5),
        if (date.proposed && date.youProposed) ...[
          Text(
            'Waiting for ${date.partner} to answer.',
            style: context.type.bodyMedium,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OdButton(
              label: 'Cancel',
              variant: OdButtonVariant.ghost,
              onPressed: _busy
                  ? null
                  : () => _change(() => _repo.cancel(date.id)),
            ),
          ),
        ] else if (date.proposed)
          Row(
            children: [
              Expanded(
                child: OdButton(
                  label: 'Not this time',
                  variant: OdButtonVariant.secondary,
                  onPressed: _busy
                      ? null
                      : () => _change(() => _repo.decline(date.id)),
                ),
              ),
              const SizedBox(width: OdSpace.x1_5),
              Expanded(
                child: OdButton(
                  label: 'Accept',
                  onPressed: _busy
                      ? null
                      : () => _change(() => _repo.accept(date.id)),
                ),
              ),
            ],
          )
        else if (date.confirmed) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share my exact location'),
            subtitle: Text(
              date.partnerSharing
                  ? '${date.partner} is sharing too. It stops when the date ends.'
                  : 'Only around the date, and only if ${date.partner} shares too.',
            ),
            value: date.sharing,
            onChanged: _busy
                ? null
                : (on) => _change(
                    () => _repo.setSharing(date.id, enabled: on),
                  ),
          ),
          if (date.partnerLat != null && date.partnerLon != null)
            Padding(
              padding: const EdgeInsets.only(bottom: OdSpace.x1),
              child: SelectableText(
                '${date.partner} shared their location'
                '${date.partnerAt == null ? '' : ' at ${whenLabel(date.partnerAt!, now)}'}: '
                '${date.partnerLat!.toStringAsFixed(5)}, ${date.partnerLon!.toStringAsFixed(5)}',
                style: context.type.bodyMedium,
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.shield_outlined, color: c.textSecondary),
            title: Text(
              date.trustedContact == null
                  ? 'Add a trusted contact'
                  : 'Trusted contact: ${date.trustedContact}',
            ),
            onTap: _busy ? null : () => _trustedContact(date),
          ),
          const SizedBox(height: OdSpace.x1),
          Row(
            children: [
              Expanded(
                child: OdButton(
                  label: 'I\'m OK',
                  variant: OdButtonVariant.secondary,
                  onPressed: _busy
                      ? null
                      : () => _reply(() => _repo.checkIn(date.id)),
                ),
              ),
              const SizedBox(width: OdSpace.x1_5),
              Expanded(
                child: OdButton(
                  label: 'SOS',
                  variant: OdButtonVariant.danger,
                  onPressed: _busy ? null : () => _sos(date),
                ),
              ),
            ],
          ),
          const SizedBox(height: OdSpace.x1),
          OdButton(
            label: 'I\'m home safe',
            expand: true,
            onPressed: _busy ? null : () => _change(() => _repo.end(date.id)),
          ),
          Center(
            child: OdButton(
              label: 'Cancel the date',
              variant: OdButtonVariant.ghost,
              onPressed: _busy
                  ? null
                  : () => _change(() => _repo.cancel(date.id)),
            ),
          ),
        ] else if (date.ended && !date.debriefSubmitted) ...[
          Text(
            'How was it? Only what you both felt is ever shared.',
            style: context.type.bodyMedium,
          ),
          const SizedBox(height: OdSpace.x1),
          OdButton(
            label: 'Share how it went',
            variant: OdButtonVariant.secondary,
            onPressed: _busy ? null : () => _debrief(date),
          ),
        ] else
          Text(switch (date.status) {
            'ENDED' => 'This date has ended. Thanks for sharing how it went.',
            'CANCELLED' => 'This date was cancelled.',
            'DECLINED' => 'This date isn\'t happening.',
            'EXPIRED' => 'This invitation expired.',
            _ => '',
          }, style: context.type.bodyMedium),
      ],
    );
  }
}

class _DebriefSheet extends StatefulWidget {
  const _DebriefSheet({required this.partner});

  final String partner;

  @override
  State<_DebriefSheet> createState() => _DebriefSheetState();
}

class _DebriefSheetState extends State<_DebriefSheet> {
  final _chosen = <DebriefAnswer>{};

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How was it?', style: context.type.titleLarge),
        const SizedBox(height: OdSpace.x0_5),
        Text(
          '${widget.partner} sees an answer only if they gave the same one. '
          'Whether you felt safe and respected stays private.',
          style: context.type.bodyMedium,
        ),
        for (final answer in DebriefAnswer.values)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(answer.label),
            value: _chosen.contains(answer),
            onChanged: (on) => setState(
              () => on == true ? _chosen.add(answer) : _chosen.remove(answer),
            ),
          ),
        const SizedBox(height: OdSpace.x1),
        OdButton(
          label: 'Send',
          expand: true,
          onPressed: () => Navigator.of(context).pop(Set.of(_chosen)),
        ),
      ],
    );
  }
}

/// Proposing: who, where (a public place) and when.
class _ProposeSheet extends ConsumerStatefulWidget {
  const _ProposeSheet();

  @override
  ConsumerState<_ProposeSheet> createState() => _ProposeSheetState();
}

class _ProposeSheetState extends ConsumerState<_ProposeSheet> {
  static const _starts = [
    ('In 2 hours', Duration(hours: 2)),
    ('This time tomorrow', Duration(hours: 24)),
    ('In 2 days', Duration(hours: 48)),
  ];

  final _place = TextEditingController();
  String? _connectionId;
  int _start = 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final connectionId = _connectionId;
    final place = _place.text.trim();
    if (connectionId == null || place.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final startsAt = DateTime.now().add(_starts[_start].$2);
    try {
      final date = await ref
          .read(datesRepositoryProvider)
          .propose(
            connectionId: connectionId,
            placeName: place,
            startsAt: startsAt,
            endsAt: startsAt.add(const Duration(hours: 2)),
          );
      if (mounted) Navigator.of(context).pop(date);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _problem(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connections =
        ref.watch(conversationsProvider).value ?? const <Conversation>[];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan a date', style: context.type.titleLarge),
            const SizedBox(height: OdSpace.x1),
            Text('With', style: context.type.titleMedium),
            if (connections.isEmpty)
              Text(
                'You can plan a date with someone you\'re connected with.',
                style: context.type.bodyMedium,
              ),
            for (final connection in connections)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(connection.firstName),
                trailing: Icon(
                  _connectionId == connection.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                onTap: () => setState(() => _connectionId = connection.id),
              ),
            const SizedBox(height: OdSpace.x1),
            TextField(
              controller: _place,
              maxLength: 160,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Where? Somewhere public (a café, a park)',
                counterText: '',
              ),
            ),
            const SizedBox(height: OdSpace.x2),
            Text('When (2 hours)', style: context.type.titleMedium),
            const SizedBox(height: OdSpace.x1),
            Wrap(
              spacing: OdSpace.x1,
              runSpacing: OdSpace.x1,
              children: [
                for (var i = 0; i < _starts.length; i++)
                  OdChip(
                    label: _starts[i].$1,
                    selected: _start == i,
                    onTap: () => setState(() => _start = i),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: OdSpace.x1),
                child: Text(
                  _error!,
                  style: context.type.bodyMedium?.copyWith(
                    color: context.od.danger,
                  ),
                ),
              ),
            const SizedBox(height: OdSpace.x2),
            OdButton(
              label: 'Send invitation',
              expand: true,
              loading: _busy,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

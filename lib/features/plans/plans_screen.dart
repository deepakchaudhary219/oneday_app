import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/plans.dart';
import '../../core/providers.dart';
import '../../core/repositories.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => switch (e) {
  LocationRequired() =>
    'Plans are shown by distance, so share your area on Nearby first.',
  ApiError(:final detail) => detail,
  _ => 'Couldn\'t reach OneDay. Check your connection and try again.',
};

/// Plans: small meet-ups (3 to 12 people) held only at Safety-Verified Meeting Points. Joining asks the host;
/// a decline is silent, so "Asked" simply stays "Asked".
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String planId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlanScreen(planId: planId)),
    );
    ref.invalidate(myPlansProvider);
    ref.invalidate(nearbyPlansProvider);
  }

  Future<void> _host(BuildContext context, WidgetRef ref) async {
    final plan = await showOdSheet<PlanDetail>(
      context,
      builder: (_) => const _HostSheet(),
    );
    if (plan == null) return;
    ref.invalidate(myPlansProvider);
    if (context.mounted) await _open(context, ref, plan.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final mine = ref.watch(myPlansProvider).value ?? const <PlanDetail>[];
    final nearby = ref.watch(nearbyPlansProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans'),
        actions: [
          TextButton(
            onPressed: () => _host(context, ref),
            child: const Text('Host a plan'),
          ),
          const SizedBox(width: OdSpace.x1),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          OdSpace.gutter,
          OdSpace.x1,
          OdSpace.gutter,
          OdSpace.x6,
        ),
        children: [
          if (mine.isNotEmpty) ...[
            Text('Your plans', style: context.type.titleMedium),
            for (final plan in mine)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(plan.title),
                subtitle: Text(
                  '${whenLabel(plan.startsAt, now)} · ${plan.place}',
                ),
                trailing: Text(
                  plan.hosting
                      ? 'Hosting'
                      : (plan.member ? 'Going' : 'Asked'),
                  style: context.type.labelMedium,
                ),
                onTap: () => _open(context, ref, plan.id),
              ),
            const SizedBox(height: OdSpace.x3),
          ],
          Text('Nearby', style: context.type.titleMedium),
          const SizedBox(height: OdSpace.x1),
          ...switch (nearby) {
            AsyncData(:final value) when value.isEmpty => [
              Text(
                'No plans near you right now. You could host one.',
                style: context.type.bodyMedium,
              ),
            ],
            AsyncData(:final value) => [
              for (final plan in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: OdSpace.x1_5),
                  child: OdCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(plan.title),
                      subtitle: Text(
                        '${whenLabel(plan.startsAt, now)} · ${plan.place}\n'
                        'Hosted by ${plan.host} · ${plan.spotsLeft} spots left'
                        '${plan.why == null ? '' : '\n${plan.why}'}',
                      ),
                      isThreeLine: true,
                      trailing: plan.you == null
                          ? null
                          : Text(
                              plan.you == 'IN' ? 'Going' : 'Asked',
                              style: context.type.labelMedium,
                            ),
                      onTap: () => _open(context, ref, plan.id),
                    ),
                  ),
                ),
            ],
            AsyncError(:final error) => [
              Text(_problem(error), style: context.type.bodyMedium),
              const SizedBox(height: OdSpace.x1),
              OdButton(
                label: 'Try again',
                variant: OdButtonVariant.secondary,
                onPressed: () => ref.invalidate(nearbyPlansProvider),
              ),
            ],
            _ => const [
              Padding(
                padding: EdgeInsets.all(OdSpace.x3),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ],
          },
        ],
      ),
    );
  }
}

/// One plan: the details, asking to join, and (for members) who's going and the Room. The host also sees who
/// asked to join.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  final _input = TextEditingController();
  PlanDetail? _plan;
  List<JoinRequest> _requests = const [];
  List<RoomMessage> _room = const [];
  String? _loadError;
  bool _busy = false;

  PlansRepository get _repo => ref.read(plansRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plan = await _repo.plan(widget.planId);
      final requests = plan.hosting
          ? await _repo.requests(plan.id)
          : const <JoinRequest>[];
      final room = plan.member
          ? await _repo.room(plan.id)
          : const <RoomMessage>[];
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _requests = requests;
        _room = room;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = _problem(e));
    }
  }

  void _say(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _do(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() => _do(() async {
    await _repo.join(widget.planId);
    await _load();
  });

  Future<void> _leave() => _do(() async {
    await _repo.leave(widget.planId);
    if (mounted) Navigator.of(context).pop();
  });

  Future<void> _decide(JoinRequest request, bool approve) => _do(() async {
    await _repo.decide(widget.planId, request.handle, approve: approve);
    await _load();
  });

  Future<void> _send({bool sendAnyway = false, String? text}) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty) return;
    try {
      final sent = await _repo.say(
        widget.planId,
        body,
        sendAnyway: sendAnyway,
      );
      if (!mounted) return;
      setState(() {
        _room = [..._room, sent];
        _input.clear();
      });
    } on EmpathyCheck catch (check) {
      if (!mounted) return;
      final anyway = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('A moment to reflect'),
          content: Text(check.reflection),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Edit message'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Send anyway'),
            ),
          ],
        ),
      );
      if (anyway == true && mounted) await _send(sendAnyway: true, text: body);
    } catch (e) {
      if (mounted) _say(_problem(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    // The Room is live: a pushed message for this plan is appended as it arrives.
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      final raw = event?.data['message'];
      if (event == null ||
          event.type != 'room' ||
          event.data['planId'] != widget.planId ||
          raw is! Map) {
        return;
      }
      final message = RoomMessage.fromJson(raw.cast<String, dynamic>());
      if (_room.any((m) => m.id == message.id)) return;
      setState(() => _room = [..._room, message]);
    });
    return Scaffold(
      appBar: AppBar(title: Text(plan?.title ?? 'Plan')),
      body: plan == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : Padding(
                      padding: const EdgeInsets.all(OdSpace.x3),
                      child: Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: context.type.bodyLarge,
                      ),
                    ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(OdSpace.gutter),
                    children: _details(context, plan),
                  ),
                ),
                if (plan.member && plan.status == 'OPEN')
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(
                      OdSpace.gutter,
                      OdSpace.x1,
                      OdSpace.gutter,
                      OdSpace.x1_5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Message the Room',
                              counterText: '',
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: OdSpace.x1),
                        OdIconButton(
                          icon: Icons.arrow_upward_rounded,
                          semanticLabel: 'Send to the Room',
                          onPressed: _send,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  List<Widget> _details(BuildContext context, PlanDetail plan) {
    final now = DateTime.now();
    return [
      Text(
        '${whenLabel(plan.startsAt, now)} to ${whenLabel(plan.endsAt, now)}',
        style: context.type.titleMedium,
      ),
      const SizedBox(height: OdSpace.x0_5),
      Text(plan.place, style: context.type.bodyLarge),
      if ((plan.address ?? '').isNotEmpty)
        Text(plan.address!, style: context.type.bodyMedium),
      const SizedBox(height: OdSpace.x1),
      Text(
        'Hosted by ${plan.host} · ${plan.activity} · ${plan.spotsLeft} spots left',
        style: context.type.bodyMedium,
      ),
      const SizedBox(height: OdSpace.x2),
      if (plan.status != 'OPEN')
        Text(
          plan.status == 'CANCELLED'
              ? 'This plan was cancelled.'
              : 'This plan has ended.',
          style: context.type.bodyLarge,
        )
      else if (plan.asked)
        Text(
          'You asked to join. The host will let you know.',
          style: context.type.bodyLarge,
        )
      else if (!plan.member)
        OdButton(
          label: 'Ask to join',
          expand: true,
          loading: _busy,
          onPressed: _join,
        ),
      if (plan.member && plan.going.isNotEmpty) ...[
        Text('Going: ${plan.going.join(', ')}', style: context.type.bodyLarge),
        const SizedBox(height: OdSpace.x1),
      ],
      if (plan.member && !plan.hosting)
        Align(
          alignment: Alignment.centerLeft,
          child: OdButton(
            label: 'Leave plan',
            variant: OdButtonVariant.ghost,
            onPressed: _busy ? null : _leave,
          ),
        ),
      if (_requests.isNotEmpty) ...[
        const SizedBox(height: OdSpace.x2),
        Text('Asking to join', style: context.type.titleMedium),
        for (final request in _requests)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(request.firstName),
            subtitle: request.sharedContext == null
                ? null
                : Text(request.sharedContext!),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _decide(request, false),
                  child: const Text('Not this time'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _decide(request, true),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
      ],
      if (plan.member) ...[
        const SizedBox(height: OdSpace.x3),
        Text('Room', style: context.type.titleMedium),
        if (_room.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: OdSpace.x1),
            child: Text(
              'Say hello and sort out the details here.',
              style: context.type.bodyMedium,
            ),
          ),
        for (final message in _room)
          Padding(
            padding: const EdgeInsets.only(top: OdSpace.x1),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: message.mine ? 'You  ' : '${message.firstName}  ',
                    style: context.type.labelLarge,
                  ),
                  TextSpan(text: message.body),
                ],
              ),
              style: context.type.bodyLarge,
            ),
          ),
      ],
    ];
  }
}

/// Hosting: pick a Safety-Verified Meeting Point, say what you're doing and when.
class _HostSheet extends ConsumerStatefulWidget {
  const _HostSheet();

  @override
  ConsumerState<_HostSheet> createState() => _HostSheetState();
}

class _HostSheetState extends ConsumerState<_HostSheet> {
  static const _starts = [
    ('In 1 hour', Duration(hours: 1)),
    ('In 3 hours', Duration(hours: 3)),
    ('This time tomorrow', Duration(hours: 24)),
  ];

  final _activity = TextEditingController();
  List<MeetingPoint>? _points;
  String? _pointId;
  int _start = 0;
  int _capacity = 6;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(plansRepositoryProvider)
        .meetingPoints()
        .then((points) {
          if (!mounted) return;
          setState(() {
            _points = points;
            _pointId = points.isEmpty ? null : points.first.id;
          });
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() {
              _points = const [];
              _error = _problem(e);
            });
          }
        });
  }

  @override
  void dispose() {
    _activity.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final activity = _activity.text.trim();
    final pointId = _pointId;
    if (activity.isEmpty || pointId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final startsAt = DateTime.now().add(_starts[_start].$2);
    try {
      final plan = await ref
          .read(plansRepositoryProvider)
          .host(
            meetingPointId: pointId,
            activity: activity,
            startsAt: startsAt,
            endsAt: startsAt.add(const Duration(hours: 2)),
            capacity: _capacity,
          );
      if (mounted) Navigator.of(context).pop(plan);
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
    final points = _points;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Host a plan', style: context.type.titleLarge),
            const SizedBox(height: OdSpace.x1_5),
            TextField(
              controller: _activity,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What are you doing? (badminton, chai, a walk)',
                counterText: '',
              ),
            ),
            const SizedBox(height: OdSpace.x2),
            Text('Where', style: context.type.titleMedium),
            if (points == null)
              const Padding(
                padding: EdgeInsets.all(OdSpace.x2),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (points.isEmpty && _error == null)
              Text(
                'There are no verified meeting points near you yet.',
                style: context.type.bodyMedium,
              )
            else
              for (final point in points)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(point.name),
                  subtitle: point.address == null ? null : Text(point.address!),
                  trailing: Icon(
                    _pointId == point.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                  ),
                  onTap: () => setState(() => _pointId = point.id),
                ),
            const SizedBox(height: OdSpace.x1),
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
            const SizedBox(height: OdSpace.x2),
            Text('Up to $_capacity people', style: context.type.titleMedium),
            Slider(
              value: _capacity.toDouble(),
              min: ApiPlans.minCapacity.toDouble(),
              max: ApiPlans.maxCapacity.toDouble(),
              divisions: ApiPlans.maxCapacity - ApiPlans.minCapacity,
              label: '$_capacity',
              onChanged: (v) => setState(() => _capacity = v.round()),
            ),
            if (_error != null)
              Text(
                _error!,
                style: context.type.bodyMedium?.copyWith(
                  color: context.od.danger,
                ),
              ),
            const SizedBox(height: OdSpace.x1),
            OdButton(
              label: 'Create plan',
              expand: true,
              loading: _busy,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}

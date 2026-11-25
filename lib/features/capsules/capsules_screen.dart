import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capsules.dart';
import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => e is ApiError
    ? e.detail
    : 'Couldn\'t reach OneDay. Check your connection and try again.';

String _day(DateTime at) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${at.day} ${months[at.month - 1]} ${at.year}';
}

/// Time Capsules: words sealed until a chosen day, for yourself or a Connection. A sealed capsule shows only
/// when it opens; on the day, it opens for both of you.
class CapsulesScreen extends ConsumerStatefulWidget {
  const CapsulesScreen({super.key});

  @override
  ConsumerState<CapsulesScreen> createState() => _CapsulesScreenState();
}

class _CapsulesScreenState extends ConsumerState<CapsulesScreen> {
  List<Capsule>? _incoming;
  List<Capsule> _sent = const [];
  String? _loadError;

  CapsuleRepository get _repo => ref.read(capsuleRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final incoming = await _repo.incoming();
      final sent = await _repo.sent();
      if (!mounted) return;
      setState(() {
        _incoming = incoming;
        _sent = sent;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = _problem(e));
    }
  }

  void _say(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _read(Capsule capsule) async {
    try {
      final full = await _repo.open(capsule.id);
      if (!mounted) return;
      await showOdSheet<void>(
        context,
        builder: (sheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              full.toSelf
                  ? 'From you, sealed until ${_day(full.opensAt)}'
                  : (full.sent
                        ? 'To ${full.withFirstName ?? 'a friend'}'
                        : 'From ${full.withFirstName ?? 'a friend'}'),
              style: sheet.type.titleLarge,
            ),
            const SizedBox(height: OdSpace.x1_5),
            if ((full.mediaUrl ?? '').isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(OdRadius.md),
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: OdMedia(url: full.mediaUrl, seed: full.id.hashCode),
                ),
              ),
              const SizedBox(height: OdSpace.x1_5),
            ],
            Text(full.message ?? '', style: sheet.type.bodyLarge),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _say(_problem(e));
    }
  }

  Future<void> _withdraw(Capsule capsule) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Withdraw this capsule?'),
        content: const Text(
          'It is deleted and will never open. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await _repo.delete(capsule.id);
      await _load();
    } catch (e) {
      if (mounted) _say(_problem(e));
    }
  }

  Future<void> _seal() async {
    final sealed = await showOdSheet<Capsule>(
      context,
      builder: (_) => const _SealSheet(),
    );
    if (sealed != null && mounted) {
      await _load();
      if (mounted) _say('Sealed until ${_day(sealed.opensAt)}.');
    }
  }

  Widget _tile(BuildContext context, Capsule capsule) {
    final who = capsule.toSelf
        ? 'To yourself'
        : (capsule.sent
              ? 'To ${capsule.withFirstName ?? 'a friend'}'
              : 'From ${capsule.withFirstName ?? 'a friend'}');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        capsule.open ? Icons.mark_email_read_outlined : Icons.lock_clock_rounded,
        color: capsule.open ? context.od.brand : context.od.textSecondary,
      ),
      title: Text(who),
      subtitle: Text(
        capsule.open
            ? 'Opened ${_day(capsule.opensAt)}'
            : 'Opens ${_day(capsule.opensAt)}',
      ),
      trailing: !capsule.open && (capsule.sent || capsule.toSelf)
          ? TextButton(
              onPressed: () => _withdraw(capsule),
              child: const Text('Withdraw'),
            )
          : null,
      onTap: capsule.open ? () => _read(capsule) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _incoming;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Capsules'),
        actions: [
          TextButton(onPressed: _seal, child: const Text('Seal one')),
          const SizedBox(width: OdSpace.x1),
        ],
      ),
      body: incoming == null
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
                Text(
                  'Write to a future day. Nobody can read it before then, not even you.',
                  style: context.type.bodyMedium,
                ),
                const SizedBox(height: OdSpace.x2),
                Text('For you', style: context.type.titleMedium),
                if (incoming.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: OdSpace.x1),
                    child: Text(
                      'No capsules from friends yet.',
                      style: context.type.bodyMedium,
                    ),
                  ),
                for (final capsule in incoming) _tile(context, capsule),
                const SizedBox(height: OdSpace.x3),
                Text('Sealed by you', style: context.type.titleMedium),
                if (_sent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: OdSpace.x1),
                    child: Text(
                      'Nothing sealed yet.',
                      style: context.type.bodyMedium,
                    ),
                  ),
                for (final capsule in _sent) _tile(context, capsule),
              ],
            ),
    );
  }
}

class _SealSheet extends ConsumerStatefulWidget {
  const _SealSheet();

  @override
  ConsumerState<_SealSheet> createState() => _SealSheetState();
}

class _SealSheetState extends ConsumerState<_SealSheet> {
  static const _when = [
    ('In a month', 30),
    ('In 6 months', 182),
    ('In a year', 365),
    ('In 5 years', 5 * 365 - 1),
  ];

  final _message = TextEditingController();
  String? _connectionId; // null: to yourself
  int _opensIn = 2;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _seal() async {
    final text = _message.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final capsule = await ref
          .read(capsuleRepositoryProvider)
          .seal(
            message: text,
            opensAt: DateTime.now().add(Duration(days: _when[_opensIn].$2)),
            connectionId: _connectionId,
          );
      if (mounted) Navigator.of(context).pop(capsule);
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
            Text('Seal a capsule', style: context.type.titleLarge),
            const SizedBox(height: OdSpace.x1_5),
            TextField(
              controller: _message,
              minLines: 3,
              maxLines: 6,
              maxLength: ApiCapsules.maxMessage,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Dear future…',
              ),
            ),
            const SizedBox(height: OdSpace.x1),
            Text('For', style: context.type.titleMedium),
            Wrap(
              spacing: OdSpace.x1,
              runSpacing: OdSpace.x1,
              children: [
                OdChip(
                  label: 'Myself',
                  selected: _connectionId == null,
                  onTap: () => setState(() => _connectionId = null),
                ),
                for (final c in connections)
                  OdChip(
                    label: c.firstName,
                    selected: _connectionId == c.id,
                    onTap: () => setState(() => _connectionId = c.id),
                  ),
              ],
            ),
            const SizedBox(height: OdSpace.x2),
            Text('Opens', style: context.type.titleMedium),
            Wrap(
              spacing: OdSpace.x1,
              runSpacing: OdSpace.x1,
              children: [
                for (var i = 0; i < _when.length; i++)
                  OdChip(
                    label: _when[i].$1,
                    selected: _opensIn == i,
                    onTap: () => setState(() => _opensIn = i),
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
              label: 'Seal it',
              expand: true,
              loading: _busy,
              onPressed: _seal,
            ),
          ],
        ),
      ),
    );
  }
}

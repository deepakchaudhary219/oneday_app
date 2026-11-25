import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amas.dart';
import '../../core/network/api_error.dart';
import '../../core/plans.dart' show whenLabel;
import '../../core/providers.dart';
import '../../core/repositories.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => e is ApiError
    ? e.detail
    : 'Couldn\'t reach OneDay. Check your connection and try again.';

String _when(Ama ama) {
  final now = DateTime.now();
  return switch (ama.state) {
    'LIVE' => 'Live now, until ${whenLabel(ama.endsAt, now)}',
    'UPCOMING' => whenLabel(ama.startsAt, now),
    'CANCELLED' => 'Cancelled',
    _ => 'Ended',
  };
}

/// AMA Corridors: a verified figure answers questions live, for everyone or for one Roots corridor. Votes order
/// the questions; only the host sees the counts.
class AmasScreen extends ConsumerWidget {
  const AmasScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AmaScreen(amaId: id)),
    );
    ref.invalidate(amasProvider);
  }

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final ama = await showOdSheet<Ama>(context, builder: (_) => const _ScheduleSheet());
    if (ama == null || !context.mounted) return;
    ref.invalidate(amasProvider);
    await _open(context, ref, ama.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amas = ref.watch(amasProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AMAs'),
        actions: [
          TextButton(
            onPressed: () => _schedule(context, ref),
            child: const Text('Host one'),
          ),
          const SizedBox(width: OdSpace.x1),
        ],
      ),
      body: switch (amas) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Padding(
            padding: const EdgeInsets.all(OdSpace.x4),
            child: Text(
              'No AMAs coming up for you right now.',
              textAlign: TextAlign.center,
              style: context.type.bodyLarge,
            ),
          ),
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(OdSpace.gutter),
          children: [
            for (final ama in value)
              Padding(
                padding: const EdgeInsets.only(bottom: OdSpace.x1_5),
                child: OdCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(ama.title),
                    subtitle: Text(
                      [
                        ama.youHost ? 'You host' : ama.hostName,
                        if (ama.corridorRegion != null) 'For ${ama.corridorRegion}',
                        _when(ama),
                      ].join(' · '),
                    ),
                    trailing: ama.live ? const OdLiveBadge() : null,
                    onTap: () => _open(context, ref, ama.id),
                  ),
                ),
              ),
          ],
        ),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(OdSpace.x3),
            child: Text(_problem(error), textAlign: TextAlign.center),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator.adaptive()),
      },
    );
  }
}

class AmaScreen extends ConsumerStatefulWidget {
  const AmaScreen({super.key, required this.amaId});

  final String amaId;

  @override
  ConsumerState<AmaScreen> createState() => _AmaScreenState();
}

class _AmaScreenState extends ConsumerState<AmaScreen> {
  final _question = TextEditingController();
  AmaDetail? _detail;
  String? _loadError;
  bool _anonymous = false;
  bool _busy = false;

  AmasRepository get _repo => ref.read(amasRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await _repo.detail(widget.amaId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _loadError = null;
        });
      }
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
      await _load();
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ask({bool sendAnyway = false, String? text}) async {
    final body = (text ?? _question.text).trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _repo.ask(widget.amaId, body, anonymous: _anonymous, sendAnyway: sendAnyway);
      _question.clear();
      await _load();
    } on EmpathyCheck catch (check) {
      if (!mounted) return;
      setState(() => _busy = false);
      final anyway = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('A moment to reflect'),
          content: Text(check.reflection),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Edit')),
            TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Ask anyway')),
          ],
        ),
      );
      if (anyway == true && mounted) await _ask(sendAnyway: true, text: body);
      return;
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answer(AmaQuestion question) async {
    final input = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(question.question),
        content: TextField(
          controller: input,
          minLines: 2,
          maxLines: 6,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Your answer'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(input.text.trim()),
            child: const Text('Answer'),
          ),
        ],
      ),
    );
    if (answer == null || answer.isEmpty || !mounted) return;
    await _do(() => _repo.answer(widget.amaId, question.id, answer));
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final ama = detail?.ama;
    final asked = detail?.questions.where((q) => q.mine).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(ama?.title ?? 'AMA')),
      body: detail == null || ama == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : Padding(
                      padding: const EdgeInsets.all(OdSpace.x3),
                      child: Text(_loadError!, textAlign: TextAlign.center),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  OdSpace.gutter,
                  OdSpace.x1,
                  OdSpace.gutter,
                  OdSpace.x6,
                ),
                children: [
                  Text(
                    [
                      ama.youHost ? 'You host' : 'With ${ama.hostName}${ama.hostHandle == null ? '' : ' (@${ama.hostHandle})'}',
                      if (ama.corridorRegion != null) 'for people from ${ama.corridorRegion}',
                    ].join(', '),
                    style: context.type.bodyLarge,
                  ),
                  Text(_when(ama), style: context.type.labelMedium),
                  if (ama.youHost && ama.upcoming)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OdButton(
                        label: 'Cancel this AMA',
                        variant: OdButtonVariant.ghost,
                        onPressed: _busy
                            ? null
                            : () => _do(() async {
                                await _repo.cancel(ama.id);
                                if (context.mounted) Navigator.of(context).pop();
                              }),
                      ),
                    ),
                  const SizedBox(height: OdSpace.x2),
                  if (ama.canAsk && asked < ApiAmas.maxQuestions) ...[
                    TextField(
                      controller: _question,
                      enabled: !_busy,
                      maxLength: 280,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ask a question (${ApiAmas.maxQuestions - asked} left)',
                        counterText: '',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ask without my name'),
                      subtitle: Text(
                        ama.corridorRegion == null
                            ? 'Shown as "Someone".'
                            : 'Shown as "Someone from ${ama.corridorRegion}".',
                      ),
                      value: _anonymous,
                      onChanged: (on) => setState(() => _anonymous = on),
                    ),
                    OdButton(label: 'Ask', expand: true, loading: _busy, onPressed: _ask),
                    const SizedBox(height: OdSpace.x3),
                  ],
                  Text('Questions', style: context.type.titleMedium),
                  if (detail.questions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: OdSpace.x1),
                      child: Text('No questions yet.', style: context.type.bodyMedium),
                    ),
                  for (final q in detail.questions)
                    Padding(
                      padding: const EdgeInsets.only(top: OdSpace.x1_5),
                      child: OdCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    q.mine ? 'You asked' : q.askedBy,
                                    style: context.type.labelLarge,
                                  ),
                                ),
                                if (q.hidden)
                                  Text('Hidden', style: context.type.labelMedium),
                                if (ama.youHost && q.votes != null)
                                  Text('${q.votes} ▲', style: context.type.labelMedium),
                              ],
                            ),
                            const SizedBox(height: OdSpace.x0_5),
                            Text(q.question, style: context.type.bodyLarge),
                            if (q.concern != null)
                              Text(
                                q.concern!,
                                style: context.type.labelMedium?.copyWith(color: context.od.textTertiary),
                              ),
                            if (q.answer != null) ...[
                              const SizedBox(height: OdSpace.x1),
                              Text(
                                ama.youHost ? 'Your answer' : '${ama.hostName} answered',
                                style: context.type.labelMedium?.copyWith(color: context.od.brand),
                              ),
                              Text(q.answer!, style: context.type.bodyLarge),
                            ],
                            Row(
                              children: [
                                if (!ama.youHost && !q.mine && q.answer == null)
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _do(() => _repo.vote(ama.id, q.id, on: !q.youVoted)),
                                    icon: Icon(
                                      q.youVoted ? Icons.arrow_upward_rounded : Icons.arrow_upward_outlined,
                                    ),
                                    label: Text(q.youVoted ? 'Voted' : 'Me too'),
                                  ),
                                if (ama.youHost && ama.live && q.answer == null)
                                  TextButton(
                                    onPressed: _busy ? null : () => _answer(q),
                                    child: const Text('Answer'),
                                  ),
                                if (ama.youHost && !q.hidden)
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _do(() => _repo.hide(ama.id, q.id)),
                                    child: const Text('Hide'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Hosting (verified figures only): a title, when, how long, and optionally one Roots corridor.
class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet();

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  static const _starts = [
    ('Tomorrow', Duration(days: 1)),
    ('In 2 days', Duration(days: 2)),
    ('In a week', Duration(days: 7)),
  ];
  static const _lengths = [30, 60, 120];

  final _title = TextEditingController();
  final _region = TextEditingController();
  int _start = 0;
  int _minutes = 60;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _region.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ama = await ref
          .read(amasRepositoryProvider)
          .schedule(
            title: title,
            startsAt: DateTime.now().add(_starts[_start].$2),
            minutes: _minutes,
            corridorRegion: _region.text,
          );
      if (mounted) Navigator.of(context).pop(ama);
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Host an AMA', style: context.type.titleLarge),
            const SizedBox(height: OdSpace.x0_5),
            Text(
              'For verified public accounts. Questions open a day before it starts.',
              style: context.type.bodyMedium,
            ),
            const SizedBox(height: OdSpace.x1_5),
            TextField(
              controller: _title,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What\'s it about?', counterText: ''),
            ),
            const SizedBox(height: OdSpace.x1),
            TextField(
              controller: _region,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Roots corridor, e.g. IN-KL (optional: everyone)',
                counterText: '',
              ),
            ),
            const SizedBox(height: OdSpace.x1),
            Text('When', style: context.type.titleMedium),
            Wrap(
              spacing: OdSpace.x1,
              children: [
                for (var i = 0; i < _starts.length; i++)
                  OdChip(
                    label: _starts[i].$1,
                    selected: _start == i,
                    onTap: () => setState(() => _start = i),
                  ),
              ],
            ),
            const SizedBox(height: OdSpace.x1),
            Text('How long', style: context.type.titleMedium),
            Wrap(
              spacing: OdSpace.x1,
              children: [
                for (final m in _lengths)
                  OdChip(
                    label: m < 60 ? '$m min' : '${m ~/ 60} h',
                    selected: _minutes == m,
                    onTap: () => setState(() => _minutes = m),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: OdSpace.x1),
                child: Text(
                  _error!,
                  style: context.type.bodyMedium?.copyWith(color: context.od.danger),
                ),
              ),
            const SizedBox(height: OdSpace.x2),
            OdButton(label: 'Schedule', expand: true, loading: _busy, onPressed: _send),
          ],
        ),
      ),
    );
  }
}

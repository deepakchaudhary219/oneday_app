import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../../core/plans.dart' show whenLabel;
import '../../core/providers.dart';
import '../../core/repositories.dart';
import '../../core/threads.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => e is ApiError
    ? e.detail
    : 'Couldn\'t reach OneDay. Check your connection and try again.';

/// Collaborative Threads: one shared story for a trip, a wedding or a festival week, among up to 12 friends.
/// Open for 1 to 7 days, then read-only, then deleted.
class ThreadsScreen extends ConsumerWidget {
  const ThreadsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ThreadScreen(threadId: id)),
    );
    ref.invalidate(threadsProvider);
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final thread = await showOdSheet<StoryThread>(
      context,
      builder: (_) => const _CreateSheet(),
    );
    if (thread == null || !context.mounted) return;
    ref.invalidate(threadsProvider);
    await _open(context, ref, thread.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(threadsProvider);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Threads'),
        actions: [
          TextButton(
            onPressed: () => _create(context, ref),
            child: const Text('Start one'),
          ),
          const SizedBox(width: OdSpace.x1),
        ],
      ),
      body: switch (threads) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Padding(
            padding: const EdgeInsets.all(OdSpace.x4),
            child: Text(
              'Going somewhere together? Start a thread and everyone adds to one story.',
              textAlign: TextAlign.center,
              style: context.type.bodyLarge,
            ),
          ),
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(OdSpace.gutter),
          children: [
            for (final thread in value)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(thread.title),
                subtitle: Text(
                  [
                    thread.members.map((m) => m.firstName).join(', '),
                    thread.open
                        ? 'open until ${whenLabel(thread.endsAt, now)}'
                        : 'ended',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
                trailing: thread.invited
                    ? Text('Invited', style: context.type.labelMedium)
                    : null,
                onTap: () => _open(context, ref, thread.id),
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

class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _input = TextEditingController();
  StoryThread? _thread;
  List<ThreadPost> _posts = const [];
  String? _loadError;
  bool _busy = false;

  ThreadsRepository get _repo => ref.read(threadsRepositoryProvider);

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
      final thread = await _repo.thread(widget.threadId);
      // Invitees see who's in, not what's been posted, until they join.
      final posts = thread.invited
          ? const <ThreadPost>[]
          : await _repo.posts(thread.id);
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _posts = posts;
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

  Future<void> _post({bool sendAnyway = false, String? text}) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty) return;
    try {
      final post = await _repo.post(
        widget.threadId,
        body,
        sendAnyway: sendAnyway,
      );
      if (!mounted) return;
      setState(() {
        _posts = [..._posts, post];
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
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Post anyway'),
            ),
          ],
        ),
      );
      if (anyway == true && mounted) await _post(sendAnyway: true, text: body);
    } catch (e) {
      if (mounted) _say(_problem(e));
    }
  }

  Future<void> _invite(StoryThread thread) async {
    final ids = await showOdSheet<List<String>>(
      context,
      builder: (_) => const _PickFriendsSheet(action: 'Invite'),
    );
    if (ids == null || ids.isEmpty) return;
    await _do(() async {
      final updated = await _repo.invite(thread.id, ids);
      if (mounted) setState(() => _thread = updated);
    });
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;
    // A new post in this thread arrives over the socket: re-read the posts.
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event?.type == 'thread' &&
          event!.data['threadId'] == widget.threadId &&
          !(thread?.invited ?? true)) {
        _repo.posts(widget.threadId).then((posts) {
          if (mounted) setState(() => _posts = posts);
        }, onError: (Object _) {});
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(thread?.title ?? 'Thread'),
        actions: [
          if (thread != null && !thread.invited)
            PopupMenuButton<String>(
              onSelected: (choice) async {
                if (choice == 'invite') await _invite(thread);
                if (choice == 'leave') {
                  await _do(() async {
                    await _repo.leave(thread.id);
                    if (context.mounted) Navigator.of(context).pop();
                  });
                }
              },
              itemBuilder: (_) => [
                if (thread.open)
                  const PopupMenuItem(value: 'invite', child: Text('Invite friends')),
                const PopupMenuItem(value: 'leave', child: Text('Leave thread')),
              ],
            ),
        ],
      ),
      body: thread == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : Padding(
                      padding: const EdgeInsets.all(OdSpace.x3),
                      child: Text(_loadError!, textAlign: TextAlign.center),
                    ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(OdSpace.gutter),
                    children: [
                      Text(
                        thread.members.map((m) => m.you ? 'You' : m.firstName).join(', '),
                        style: context.type.bodyMedium,
                      ),
                      Text(
                        thread.open
                            ? 'Open until ${whenLabel(thread.endsAt, DateTime.now())}'
                            : 'This thread has ended. It\'s read-only and will be deleted soon.',
                        style: context.type.labelMedium,
                      ),
                      const SizedBox(height: OdSpace.x2),
                      if (thread.invited) ...[
                        Text(
                          'You\'re invited. Join to see and add to the story.',
                          style: context.type.bodyLarge,
                        ),
                        const SizedBox(height: OdSpace.x1_5),
                        Row(
                          children: [
                            Expanded(
                              child: OdButton(
                                label: 'Not this time',
                                variant: OdButtonVariant.secondary,
                                onPressed: _busy
                                    ? null
                                    : () => _do(() async {
                                        await _repo.decline(thread.id);
                                        if (context.mounted) Navigator.of(context).pop();
                                      }),
                              ),
                            ),
                            const SizedBox(width: OdSpace.x1_5),
                            Expanded(
                              child: OdButton(
                                label: 'Join',
                                loading: _busy,
                                onPressed: () => _do(() async {
                                  await _repo.accept(thread.id);
                                  await _load();
                                }),
                              ),
                            ),
                          ],
                        ),
                      ] else if (_posts.isEmpty)
                        Text(
                          'Nothing yet. Add the first line.',
                          style: context.type.bodyMedium,
                        ),
                      for (final post in _posts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: OdSpace.x1_5),
                          child: OdCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        post.mine ? 'You' : post.firstName,
                                        style: context.type.labelLarge,
                                      ),
                                    ),
                                    if (post.mine)
                                      IconButton(
                                        tooltip: 'Delete post',
                                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                        onPressed: () => _do(() async {
                                          await _repo.deletePost(thread.id, post.id);
                                          if (mounted) {
                                            setState(
                                              () => _posts = [
                                                for (final p in _posts)
                                                  if (p.id != post.id) p,
                                              ],
                                            );
                                          }
                                        }),
                                      ),
                                  ],
                                ),
                                if ((post.mediaUrl ?? '').isNotEmpty) ...[
                                  const SizedBox(height: OdSpace.x1),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(OdRadius.md),
                                    child: AspectRatio(
                                      aspectRatio: 4 / 5,
                                      child: OdMedia(
                                        url: post.mediaUrl,
                                        seed: post.id.hashCode,
                                      ),
                                    ),
                                  ),
                                ],
                                if ((post.caption ?? '').isNotEmpty) ...[
                                  const SizedBox(height: OdSpace.x0_5),
                                  Text(post.caption!, style: context.type.bodyLarge),
                                ],
                                if (post.concern != null) ...[
                                  const SizedBox(height: OdSpace.x0_5),
                                  Text(
                                    post.concern!,
                                    style: context.type.labelMedium?.copyWith(
                                      color: context.od.textTertiary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!thread.invited && thread.open)
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
                            maxLines: 3,
                            maxLength: ApiThreads.maxCaption,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Add to the story',
                              counterText: '',
                            ),
                            onSubmitted: (_) => _post(),
                          ),
                        ),
                        const SizedBox(width: OdSpace.x1),
                        OdIconButton(
                          icon: Icons.arrow_upward_rounded,
                          semanticLabel: 'Post to the thread',
                          onPressed: _post,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CreateSheet extends ConsumerStatefulWidget {
  const _CreateSheet();

  @override
  ConsumerState<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends ConsumerState<_CreateSheet> {
  final _title = TextEditingController();
  final _invite = <String>{};
  int _days = 3;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final thread = await ref
          .read(threadsRepositoryProvider)
          .create(title, days: _days, inviteConnectionIds: _invite.toList());
      if (mounted) Navigator.of(context).pop(thread);
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
            Text('Start a thread', style: context.type.titleLarge),
            const SizedBox(height: OdSpace.x1_5),
            TextField(
              controller: _title,
              maxLength: ApiThreads.maxTitle,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Goa trip, Meera\'s wedding, Onam week…',
                counterText: '',
              ),
            ),
            const SizedBox(height: OdSpace.x1),
            Text('Open for $_days ${_days == 1 ? 'day' : 'days'}', style: context.type.titleMedium),
            Slider(
              value: _days.toDouble(),
              min: 1,
              max: 7,
              divisions: 6,
              label: '$_days',
              onChanged: (v) => setState(() => _days = v.round()),
            ),
            Text('Invite', style: context.type.titleMedium),
            if (connections.isEmpty)
              Text(
                'You can invite people you\'re connected with.',
                style: context.type.bodyMedium,
              ),
            for (final c in connections)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(c.firstName),
                value: _invite.contains(c.id),
                onChanged: (on) => setState(() {
                  if (on == true && _invite.length < ApiThreads.maxMembers - 1) {
                    _invite.add(c.id);
                  } else {
                    _invite.remove(c.id);
                  }
                }),
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
            OdButton(
              label: 'Start thread',
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

/// Picks Connections; returns their connection ids.
class _PickFriendsSheet extends ConsumerStatefulWidget {
  const _PickFriendsSheet({required this.action});

  final String action;

  @override
  ConsumerState<_PickFriendsSheet> createState() => _PickFriendsSheetState();
}

class _PickFriendsSheetState extends ConsumerState<_PickFriendsSheet> {
  final _chosen = <String>{};

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
            Text('${widget.action} friends', style: context.type.titleLarge),
            for (final c in connections)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(c.firstName),
                value: _chosen.contains(c.id),
                onChanged: (on) => setState(
                  () => on == true ? _chosen.add(c.id) : _chosen.remove(c.id),
                ),
              ),
            const SizedBox(height: OdSpace.x1_5),
            OdButton(
              label: widget.action,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_chosen.toList()),
            ),
          ],
        ),
      ),
    );
  }
}

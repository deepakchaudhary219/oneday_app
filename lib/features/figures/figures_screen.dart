import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/figures.dart';
import '../../core/models.dart' show ago;
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => switch (e) {
  FigureNotFound() => 'No verified account with that handle.',
  ApiError(:final detail) => detail,
  _ => 'Couldn\'t reach OneDay. Check your connection and try again.',
};

/// Public Figures: staff-verified creators, artists, athletes, journalists, officials and organisations, followed
/// one way. Following opens no message channel, and nobody sees follower counts except the figure.
class FiguresScreen extends ConsumerStatefulWidget {
  const FiguresScreen({super.key});

  @override
  ConsumerState<FiguresScreen> createState() => _FiguresScreenState();
}

class _FiguresScreenState extends ConsumerState<FiguresScreen> {
  final _search = TextEditingController();
  List<Figure> _following = const [];
  List<FigurePost> _feed = const [];
  MyFigure? _mine;
  Figure? _found;
  String? _searchProblem;
  bool _loading = true;
  String? _loadError;

  FiguresRepository get _repo => ref.read(figuresRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final following = await _repo.following();
      final feed = await _repo.feed();
      MyFigure? mine;
      try {
        mine = await _repo.mine();
      } catch (_) {
        mine = null;
      }
      if (!mounted) return;
      setState(() {
        _following = following;
        _feed = feed;
        _mine = mine;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = _problem(e);
        });
      }
    }
  }

  Future<void> _find() async {
    final handle = ApiFigures.normalise(_search.text);
    if (handle.isEmpty) return;
    setState(() {
      _found = null;
      _searchProblem = null;
    });
    if (!ApiFigures.handlePattern.hasMatch(handle)) {
      setState(() => _searchProblem = 'Handles are 3 to 30 of a-z, 0-9, _ and .');
      return;
    }
    try {
      final figure = await _repo.figure(handle);
      if (mounted) setState(() => _found = figure);
    } catch (e) {
      if (mounted) setState(() => _searchProblem = _problem(e));
    }
  }

  Future<void> _toggle(Figure figure) async {
    try {
      if (figure.following) {
        await _repo.unfollow(figure.handle);
      } else {
        await _repo.follow(figure.handle);
      }
      final refreshed = await _repo.figure(figure.handle);
      if (mounted && _found?.handle == figure.handle) {
        setState(() => _found = refreshed);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_problem(e))));
      }
    }
  }

  Future<void> _apply() async {
    final applied = await showOdSheet<MyFigure>(
      context,
      builder: (_) => const _ApplySheet(),
    );
    if (applied != null && mounted) {
      setState(() => _mine = applied);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent. Our team reviews applications by hand.')),
      );
    }
  }

  Widget _figureTile(Figure figure) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: OdAvatar(name: figure.publicName, seed: figure.handle.hashCode, size: 40),
    title: Row(
      children: [
        Flexible(child: Text(figure.publicName, overflow: TextOverflow.ellipsis)),
        if (figure.verified) ...[
          const SizedBox(width: 4),
          Icon(Icons.verified_rounded, size: 16, color: context.od.brand),
        ],
      ],
    ),
    subtitle: Text(
      [
        '@${figure.handle}',
        if (figure.category != null) figure.category!.label,
      ].join(' · '),
    ),
    trailing: TextButton(
      onPressed: () => _toggle(figure),
      child: Text(figure.following ? 'Following' : 'Follow'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mine = _mine;
    return Scaffold(
      appBar: AppBar(title: const Text('Public figures')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                OdSpace.gutter,
                OdSpace.x1,
                OdSpace.gutter,
                OdSpace.x6,
              ),
              children: [
                if (_loadError != null) ...[
                  Text(_loadError!, style: context.type.bodyLarge),
                  const SizedBox(height: OdSpace.x2),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        autocorrect: false,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(hintText: 'Find by @handle'),
                        onSubmitted: (_) => _find(),
                      ),
                    ),
                    const SizedBox(width: OdSpace.x1),
                    OdIconButton(
                      icon: Icons.search_rounded,
                      semanticLabel: 'Find',
                      onPressed: _find,
                    ),
                  ],
                ),
                if (_searchProblem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: OdSpace.x1),
                    child: Text(_searchProblem!, style: context.type.bodyMedium),
                  ),
                if (_found != null) ...[
                  _figureTile(_found!),
                  if ((_found!.bio ?? '').isNotEmpty)
                    Text(_found!.bio!, style: context.type.bodyMedium),
                ],
                const SizedBox(height: OdSpace.x3),
                Text('Following', style: context.type.titleMedium),
                if (_following.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: OdSpace.x1),
                    child: Text(
                      'Follow a figure by their handle to see their stories here.',
                      style: context.type.bodyMedium,
                    ),
                  ),
                for (final figure in _following) _figureTile(figure),
                if (_feed.isNotEmpty) ...[
                  const SizedBox(height: OdSpace.x3),
                  Text('Their stories today', style: context.type.titleMedium),
                  const SizedBox(height: OdSpace.x1),
                  for (final post in _feed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: OdSpace.x1_5),
                      child: OdCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                '@${post.handle}',
                                if (post.postedAt != null) ago(now.difference(post.postedAt!)),
                              ].join(' · '),
                              style: context.type.labelLarge,
                            ),
                            if ((post.mediaUrl ?? '').isNotEmpty) ...[
                              const SizedBox(height: OdSpace.x1),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(OdRadius.md),
                                child: AspectRatio(
                                  aspectRatio: 4 / 5,
                                  child: OdMedia(
                                    url: post.mediaUrl,
                                    seed: post.momentId.hashCode,
                                    activity: post.activity,
                                  ),
                                ),
                              ),
                            ],
                            if ((post.caption ?? '').isNotEmpty) ...[
                              const SizedBox(height: OdSpace.x0_5),
                              Text(post.caption!, style: context.type.bodyLarge),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: OdSpace.x4),
                if (mine == null)
                  OdButton(
                    label: 'Apply for a public account',
                    variant: OdButtonVariant.secondary,
                    expand: true,
                    onPressed: _apply,
                  )
                else
                  Text(
                    switch (mine.status) {
                      'APPROVED' =>
                        'You are @${mine.handle}${mine.followers == null ? '' : ' · ${mine.followers} following you (only you see this)'}.',
                      'PENDING' => 'Your application for @${mine.handle} is being reviewed.',
                      'REJECTED' => 'Your application for @${mine.handle} wasn\'t approved.',
                      _ => '@${mine.handle} is no longer a public account.',
                    },
                    style: context.type.bodyMedium,
                  ),
              ],
            ),
    );
  }
}

class _ApplySheet extends ConsumerStatefulWidget {
  const _ApplySheet();

  @override
  ConsumerState<_ApplySheet> createState() => _ApplySheetState();
}

class _ApplySheetState extends ConsumerState<_ApplySheet> {
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _evidence = TextEditingController();
  FigureCategory _category = FigureCategory.creator;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _handle.dispose();
    _name.dispose();
    _bio.dispose();
    _evidence.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final handle = ApiFigures.normalise(_handle.text);
    if (!ApiFigures.handlePattern.hasMatch(handle)) {
      setState(() => _error = 'Handles are 3 to 30 of a-z, 0-9, _ and .');
      return;
    }
    if (_name.text.trim().isEmpty || _evidence.text.trim().isEmpty || _busy) {
      setState(() => _error = 'Add your public name and how we can check it\'s you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final applied = await ref
          .read(figuresRepositoryProvider)
          .apply(
            handle: handle,
            publicName: _name.text,
            category: _category,
            evidence: _evidence.text,
            bio: _bio.text,
          );
      if (mounted) Navigator.of(context).pop(applied);
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
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Apply for a public account', style: context.type.titleLarge),
            const SizedBox(height: OdSpace.x0_5),
            Text(
              'A person on our team checks every application. Your personal profile stays separate.',
              style: context.type.bodyMedium,
            ),
            const SizedBox(height: OdSpace.x1_5),
            TextField(
              controller: _handle,
              autocorrect: false,
              maxLength: 30,
              decoration: const InputDecoration(hintText: 'Handle (e.g. chef.ranveer)', counterText: ''),
            ),
            const SizedBox(height: OdSpace.x1),
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Public name', counterText: ''),
            ),
            const SizedBox(height: OdSpace.x1),
            Wrap(
              spacing: OdSpace.x1,
              runSpacing: OdSpace.x1,
              children: [
                for (final c in FigureCategory.values)
                  OdChip(
                    label: c.label,
                    selected: _category == c,
                    onTap: () => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: OdSpace.x1),
            TextField(
              controller: _bio,
              maxLength: 280,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Bio (optional)', counterText: ''),
            ),
            const SizedBox(height: OdSpace.x1),
            TextField(
              controller: _evidence,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'How can we check it\'s you? Links to your official pages, press, a team contact…',
                counterText: '',
              ),
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
            OdButton(label: 'Send application', expand: true, loading: _busy, onPressed: _send),
          ],
        ),
      ),
    );
  }
}

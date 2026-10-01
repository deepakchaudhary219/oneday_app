import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../design_system/design_system.dart';

/// Opens a story full-screen with a scale-and-fade transition from where it was tapped.
Future<void> openStory(BuildContext context, List<Story> stories, int index) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: OdMotion.of(context, OdMotion.standard),
      reverseTransitionDuration: OdMotion.of(context, OdMotion.quick),
      pageBuilder: (context, animation, _) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(
            begin: 0.92,
            end: 1.0,
          ).animate(CurvedAnimation(parent: animation, curve: OdMotion.enter)),
          child: StoryViewer(stories: stories, initialStory: index),
        ),
      ),
    ),
  );
}

/// The story viewer people already know (Instagram and Snapchat): tap right for next, left for back, hold to
/// pause, swipe down to close, with the content following the finger. Stories advance to the next person and
/// close after the last one, with no autoplay into anything else.
class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.stories,
    this.initialStory = 0,
    this.frameDuration = const Duration(seconds: 5),
  });

  final List<Story> stories;
  final int initialStory;
  final Duration frameDuration;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  late int _story = widget.initialStory;
  int _frame = 0;
  double _drag = 0;
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: widget.frameDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _next();
        })
        ..forward();

  Story get _current => widget.stories[_story];

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _next() {
    if (_frame < _current.frames.length - 1) {
      setState(() => _frame++);
    } else if (_story < widget.stories.length - 1) {
      setState(() {
        _story++;
        _frame = 0;
      });
    } else {
      Navigator.of(context).maybePop();
      return;
    }
    HapticFeedback.selectionClick();
    _progress.forward(from: 0);
  }

  void _previous() {
    if (_frame > 0) {
      setState(() => _frame--);
    } else if (_story > 0) {
      setState(() {
        _story--;
        _frame = widget.stories[_story].frames.length - 1;
      });
    }
    _progress.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final frame = _current.frames[_frame];
    final padding = MediaQuery.paddingOf(context);
    final dismiss = (_drag / 400).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTapUp: (d) =>
            d.localPosition.dx < MediaQuery.sizeOf(context).width / 3
            ? _previous()
            : _next(),
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        onVerticalDragStart: (_) => _progress.stop(),
        onVerticalDragUpdate: (d) =>
            setState(() => _drag = (_drag + d.delta.dy).clamp(0.0, 600.0)),
        onVerticalDragEnd: (d) {
          if (_drag > 140 || (d.primaryVelocity ?? 0) > 900) {
            Navigator.of(context).maybePop();
          } else {
            setState(() => _drag = 0);
            _progress.forward();
          }
        },
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 1 - dismiss * 0.7),
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: Transform.scale(
              scale: 1 - dismiss * 0.15,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  _drag > 0 ? OdRadius.lg : 0,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: OdMotion.of(context, OdMotion.quick),
                      child: OdMedia(
                        key: ValueKey('$_story-$_frame'),
                        seed: frame.seed,
                        url: frame.mediaUrl,
                      ),
                    ),
                    const OdScrim(top: 0.22, bottom: 0.3),
                    Positioned(
                      top: padding.top + OdSpace.x1,
                      left: OdSpace.x1,
                      right: OdSpace.x1,
                      child: Column(
                        children: [
                          _Segments(
                            count: _current.frames.length,
                            index: _frame,
                            progress: _progress,
                          ),
                          const SizedBox(height: OdSpace.x1_5),
                          Row(
                            children: [
                              OdAvatar(
                                name: _current.firstName,
                                size: 34,
                                seed: _current.seed,
                              ),
                              const SizedBox(width: OdSpace.x1),
                              Flexible(
                                child: Text(
                                  _current.firstName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.type.titleMedium?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: OdSpace.x1),
                              Text(
                                frame.postedAgo,
                                style: context.type.labelMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                              const Spacer(),
                              OdIconButton(
                                icon: Icons.close_rounded,
                                semanticLabel: 'Close story',
                                background: Colors.transparent,
                                foreground: Colors.white,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (frame.caption != null || frame.activity != null)
                      Positioned(
                        left: OdSpace.gutter,
                        right: OdSpace.gutter,
                        bottom: padding.bottom + 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (frame.activity != null)
                              OdFrosted(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: OdSpace.x1_5,
                                  vertical: 6,
                                ),
                                child: Text(
                                  '#${frame.activity}',
                                  style: context.type.labelMedium?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (frame.caption != null) ...[
                              const SizedBox(height: OdSpace.x1),
                              Text(
                                frame.caption!,
                                style: context.type.titleLarge?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (!_current.mine)
                      Positioned(
                        left: OdSpace.gutter,
                        right: OdSpace.gutter,
                        bottom: padding.bottom + OdSpace.x2,
                        child: OdFrosted(
                          padding: const EdgeInsets.symmetric(
                            horizontal: OdSpace.x2,
                            vertical: OdSpace.x1_5,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Reply to ${_current.firstName}…',
                                  style: context.type.bodyMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.favorite_border_rounded,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.count,
    required this.index,
    required this.progress,
  });

  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: i < index
                    ? const FractionallySizedBox(widthFactor: 1, child: _Fill())
                    : i == index
                    ? AnimatedBuilder(
                        animation: progress,
                        builder: (_, _) => FractionallySizedBox(
                          widthFactor: progress.value,
                          child: const _Fill(),
                        ),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

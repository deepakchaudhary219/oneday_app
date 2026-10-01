import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repositories.dart';
import '../../design_system/design_system.dart';

/// A conversation. Messages send optimistically (they appear at once, then settle). There are no read receipts
/// and no typing indicators, so there's nothing to watch and wait on. When the Empathy Mirror flags a message,
/// a calm sheet offers Edit or Send anyway.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  List<ChatMessage>? _messages;

  @override
  void initState() {
    super.initState();
    ref
        .read(chatRepositoryProvider)
        .history(widget.conversation.conversationId ?? widget.conversation.id)
        .then((list) {
          if (mounted) setState(() => _messages = List.of(list));
        });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send({bool sendAnyway = false, String? text}) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty) return;
    final draft = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      mine: true,
      body: body,
      sentAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _messages = [...?_messages, draft];
      _input.clear();
    });
    try {
      final sent = await ref
          .read(chatRepositoryProvider)
          .send(
            widget.conversation.conversationId ?? widget.conversation.id,
            body,
            sendAnyway: sendAnyway,
          );
      if (!mounted) return;
      setState(
        () => _messages = [
          for (final m in _messages!) m.id == draft.id ? sent.confirmed() : m,
        ],
      );
    } on EmpathyCheck catch (check) {
      if (!mounted) return;
      setState(
        () => _messages = _messages!.where((m) => m.id != draft.id).toList(),
      );
      final choice = await showOdSheet<bool>(
        context,
        builder: (_) => _EmpathySheet(reflection: check.reflection, text: body),
      );
      if (!mounted) return;
      if (choice == true) {
        await _send(sendAnyway: true, text: body);
      } else {
        _input.text = body; // back to editing, nothing lost
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final conv = widget.conversation;
    final messages = _messages;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            OdWarmthGlow(
              level: conv.warmth,
              child: OdAvatar(name: conv.firstName, size: 36, seed: conv.seed),
            ),
            const SizedBox(width: OdSpace.x1_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conv.firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.titleMedium,
                  ),
                  if (conv.encrypted)
                    Row(
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 11,
                          color: c.textTertiary,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            'End-to-end encrypted',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.type.labelSmall,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OdIconButton(
            icon: Icons.call_rounded,
            semanticLabel: 'Voice call',
            onPressed: () {},
          ),
          OdIconButton(
            icon: Icons.more_horiz_rounded,
            semanticLabel: 'Safety and options',
            onPressed: () => _safety(context),
          ),
          const SizedBox(width: OdSpace.x1),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(OdSpace.gutter),
                    itemCount: messages.length,
                    itemBuilder: (context, i) =>
                        _Bubble(message: messages[messages.length - 1 - i]),
                  ),
          ),
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
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Message'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: OdSpace.x1),
                ListenableBuilder(
                  listenable: _input,
                  builder: (context, _) => AnimatedScale(
                    scale: _input.text.trim().isEmpty ? 0.85 : 1,
                    duration: OdMotion.of(context, OdMotion.quick),
                    child: OdIconButton(
                      icon: Icons.arrow_upward_rounded,
                      semanticLabel: 'Send',
                      background: _input.text.trim().isEmpty
                          ? c.surfaceRaised
                          : c.brand,
                      foreground: _input.text.trim().isEmpty
                          ? c.textTertiary
                          : c.onBrand,
                      onPressed: _input.text.trim().isEmpty ? null : _send,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _safety(BuildContext context) {
    showOdSheet<void>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.flag_rounded),
            title: const Text('Report'),
            onTap: () => Navigator.of(context).pop(),
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: const Text('Block'),
            onTap: () => Navigator.of(context).pop(),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Leave quietly'),
            subtitle: const Text('They won\'t be told'),
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final mine = message.mine;
    return TweenAnimationBuilder<double>(
      key: ValueKey(message.id),
      tween: Tween(begin: 0, end: 1),
      duration: OdMotion.of(context, OdMotion.standard),
      curve: OdMotion.enter,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(
            horizontal: OdSpace.x1_5,
            vertical: OdSpace.x1,
          ),
          decoration: BoxDecoration(
            gradient: mine ? c.brandGradient : null,
            color: mine ? null : c.surfaceRaised,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(OdRadius.lg),
              topRight: const Radius.circular(OdRadius.lg),
              bottomLeft: Radius.circular(mine ? OdRadius.lg : OdRadius.sm),
              bottomRight: Radius.circular(mine ? OdRadius.sm : OdRadius.lg),
            ),
          ),
          child: AnimatedOpacity(
            opacity: message.pending ? 0.6 : 1,
            duration: OdMotion.of(context, OdMotion.quick),
            child: Text(
              message.body,
              style: context.type.bodyLarge?.copyWith(
                color: mine ? c.onBrand : c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reflection, not rejection: the wording is warm, editing is the default, and sending anyway is always
/// possible (it's a nudge, not a filter).
class _EmpathySheet extends StatelessWidget {
  const _EmpathySheet({required this.reflection, required this.text});

  final String reflection;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.spa_rounded, color: c.safety),
            const SizedBox(width: OdSpace.x1),
            Expanded(
              child: Text(
                'A moment to reflect',
                style: context.type.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: OdSpace.x1_5),
        Text(reflection, style: context.type.bodyLarge),
        const SizedBox(height: OdSpace.x1_5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(OdSpace.x1_5),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(OdRadius.md),
          ),
          child: Text('"$text"', style: context.type.bodyMedium),
        ),
        const SizedBox(height: OdSpace.x3),
        OdButton(
          label: 'Edit message',
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: OdSpace.x1),
        Center(
          child: OdButton(
            label: 'Send anyway',
            variant: OdButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
  }
}

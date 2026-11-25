import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/e2ee.dart';
import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/realtime.dart';
import '../../core/repositories.dart';
import '../../core/safety.dart';
import '../../design_system/design_system.dart';
import '../calls/call_screen.dart';
import '../safety/safety_sheet.dart';

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

  /// Investment Balance: a private line when the other person has been carrying the conversation.
  String? _balance;

  /// Once a chat is encrypted it never goes back to plaintext.
  late bool _encrypted = widget.conversation.encrypted;

  /// Decrypted on this phone, by message id: the only place encrypted messages are readable.
  Map<String, DecryptedMessage> _decrypted = const {};

  String get _conversationId =>
      widget.conversation.conversationId ?? widget.conversation.id;

  @override
  void initState() {
    super.initState();
    final chat = ref.read(chatRepositoryProvider);
    _loadHistory();
    chat
        .balanceNudge(_conversationId)
        .then((line) {
          if (mounted && line != null) setState(() => _balance = line);
        })
        .catchError((Object _) {}); // a hint, never an error on screen
  }

  /// The server's history with encrypted messages filled in from this phone's decrypted copies.
  Future<void> _loadHistory() async {
    final secure = ref.read(encryptedChatProvider);
    try {
      if (secure != null && _encrypted) await secure.receive();
    } catch (_) {
      // The inbox can wait; history still loads.
    }
    try {
      final list = await ref.read(chatRepositoryProvider).history(_conversationId);
      final local = secure == null
          ? const <DecryptedMessage>[]
          : await secure.history(_conversationId);
      if (!mounted) return;
      final byId = {for (final m in local) m.messageId: m};
      final shown = <String>{};
      final merged = [
        for (final m in list)
          if (byId[m.id] case final d?) d.toChat() else m,
      ];
      shown.addAll(merged.map((m) => m.id));
      // Older decrypted messages than the server's page still belong in the thread.
      final older = [
        for (final d in local)
          if (!shown.contains(d.messageId)) d.toChat(),
      ];
      setState(() {
        _decrypted = byId;
        _encrypted = _encrypted || local.isNotEmpty;
        _messages = [...older, ...merged]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      });
    } catch (_) {
      if (mounted) setState(() => _messages ??= const []);
    }
  }

  Future<void> _turnOnEncryption() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Turn on end-to-end encryption?'),
        content: Text(
          'From now on only you and ${widget.conversation.firstName} can read this chat, on your own phones. '
          'It can\'t be turned off, and new messages are kept only on your devices.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Turn on')),
        ],
      ),
    );
    if (sure == true && mounted) setState(() => _encrypted = true);
  }

  /// Reports a decrypted message with its franking key, which proves to the safety team what was sent.
  Future<void> _reportEncrypted(ChatMessage message) async {
    final decrypted = _decrypted[message.id];
    final secure = ref.read(encryptedChatProvider);
    if (message.mine || decrypted == null || secure == null) return;
    final category = await showOdSheet<ReportCategory>(
      context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report this message?', style: sheet.type.titleLarge),
          Text(
            'Reporting shares this one message with our safety team, with proof it was sent as shown.',
            style: sheet.type.bodyMedium,
          ),
          for (final c in ReportCategory.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(c.label),
              onTap: () => Navigator.of(sheet).pop(c),
            ),
        ],
      ),
    );
    if (category == null || !mounted) return;
    try {
      final said = await secure.report(
        conversationId: _conversationId,
        message: decrypted,
        category: category.api,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiError ? e.detail : 'Couldn\'t send the report.')),
        );
      }
    }
  }

  /// A message pushed over the socket: theirs, or mine from another device.
  void _arrived(RealtimeEvent event) {
    if (event.type == 'e2ee') {
      if (event.data['conversationId'] == _conversationId) _loadHistory();
      return;
    }
    if (event.type != 'message' ||
        event.data['conversationId'] != _conversationId) {
      return;
    }
    final raw = event.data['message'];
    final current = _messages;
    if (raw is! Map || current == null) return;
    final message = ChatMessage.fromJson(raw.cast<String, dynamic>());
    if (current.any((m) => m.id == message.id)) return;
    // My own send echoes back before the HTTP answer settles the optimistic bubble.
    if (message.mine &&
        current.any((m) => m.pending && m.body == message.body)) {
      return;
    }
    setState(() => _messages = [...current, message]);
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
      final secure = ref.read(encryptedChatProvider);
      ChatMessage sent;
      if (_encrypted && secure != null) {
        sent = await secure.send(
          conversationId: _conversationId,
          connectionId: widget.conversation.id,
          body: body,
        );
        final local = await secure.history(_conversationId);
        _decrypted = {for (final m in local) m.messageId: m};
      } else {
        try {
          sent = await ref
              .read(chatRepositoryProvider)
              .send(_conversationId, body, sendAnyway: sendAnyway);
        } on ApiError catch (e) {
          // The other side turned encryption on: this chat is encrypted from now on.
          if (e.code != 'E2EE_REQUIRED' || secure == null) rethrow;
          _encrypted = true;
          sent = await secure.send(
            conversationId: _conversationId,
            connectionId: widget.conversation.id,
            body: body,
          );
        }
      }
      if (!mounted) return;
      setState(
        () => _messages = [
          for (final m in _messages!)
            if (m.id == draft.id)
              sent.confirmed()
            else if (m.id != sent.id) // the socket may have delivered it already
              m,
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
    } catch (e) {
      if (!mounted) return;
      // Not sent: the words go back to the box, and the reason is shown.
      setState(
        () => _messages = _messages!.where((m) => m.id != draft.id).toList(),
      );
      _input.text = body;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiError ? e.detail : 'Couldn\'t send. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final conv = widget.conversation;
    final messages = _messages;
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event != null) _arrived(event);
    });
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
                  if (_encrypted)
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
          if (!_encrypted && ref.read(encryptedChatProvider) != null)
            OdIconButton(
              icon: Icons.lock_open_rounded,
              semanticLabel: 'Turn on end-to-end encryption',
              onPressed: _turnOnEncryption,
            ),
          OdIconButton(
            icon: Icons.call_rounded,
            semanticLabel: 'Call',
            onPressed: () => startCall(context, ref, conv),
          ),
          OdIconButton(
            icon: Icons.more_horiz_rounded,
            semanticLabel: 'Safety and options',
            onPressed: _safety,
          ),
          const SizedBox(width: OdSpace.x1),
        ],
      ),
      body: Column(
        children: [
          if (_balance != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OdSpace.gutter,
                OdSpace.x1,
                OdSpace.gutter,
                0,
              ),
              child: Text(
                _balance!,
                textAlign: TextAlign.center,
                style: context.type.labelMedium?.copyWith(
                  color: c.textTertiary,
                ),
              ),
            ),
          Expanded(
            child: messages == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(OdSpace.gutter),
                    itemCount: messages.length,
                    itemBuilder: (context, i) =>
                        GestureDetector(
                          onLongPress: () => _reportEncrypted(
                            messages[messages.length - 1 - i],
                          ),
                          child: _Bubble(
                            message: messages[messages.length - 1 - i],
                          ),
                        ),
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

  Future<void> _safety() async {
    final conv = widget.conversation;
    final outcome = await showSafetySheet(
      context,
      target: SafetyTarget.connection(conv.id),
      firstName: conv.firstName,
      connectionId: conv.id,
    );
    if (!mounted || outcome == null) return;
    if (outcome != SafetyOutcome.reported) {
      // Blocked or left: the chat is over, so it leaves the list and the screen.
      ref.invalidate(conversationsProvider);
      Navigator.of(context).pop();
    }
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

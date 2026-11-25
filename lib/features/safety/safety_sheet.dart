import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/safety.dart';
import '../../design_system/design_system.dart';

/// What the person did in the safety sheet; the caller removes what should no longer be on screen.
enum SafetyOutcome { reported, blocked, left }

/// Report, block and (for a Connection) leave quietly: one sheet, the same everywhere another person appears.
/// Nothing here notifies the other person.
Future<SafetyOutcome?> showSafetySheet(
  BuildContext context, {
  required SafetyTarget target,
  required String firstName,
  String? connectionId,
}) => showOdSheet<SafetyOutcome>(
  context,
  builder: (_) => _SafetySheet(
    target: target,
    firstName: firstName,
    connectionId: connectionId,
  ),
);

enum _Step { menu, report, block, leave }

class _SafetySheet extends ConsumerStatefulWidget {
  const _SafetySheet({
    required this.target,
    required this.firstName,
    this.connectionId,
  });

  final SafetyTarget target;
  final String firstName;
  final String? connectionId;

  @override
  ConsumerState<_SafetySheet> createState() => _SafetySheetState();
}

class _SafetySheetState extends ConsumerState<_SafetySheet> {
  final _details = TextEditingController();
  _Step _step = _Step.menu;
  ReportCategory? _category;
  bool _alsoBlock = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  /// Runs the action, says what happened once the sheet has closed, and keeps the sheet open on failure.
  Future<void> _run(
    Future<String> Function(SafetyRepository safety) action,
    SafetyOutcome outcome,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final said = await action(ref.read(safetyRepositoryProvider));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(outcome);
      messenger.showSnackBar(SnackBar(content: Text(said)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiError
            ? e.detail
            : 'Couldn\'t do that. Check your connection and try again.';
      });
    }
  }

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: switch (_step) {
            _Step.menu => _menu(context),
            _Step.report => _report(context),
            _Step.block => _confirm(
              context,
              title: 'Block ${widget.firstName}?',
              body:
                  'You won\'t see each other anywhere on OneDay, and any chat between you closes. '
                  '${widget.firstName} won\'t be told.',
              action: 'Block',
              onConfirm: () => _run((safety) async {
                await safety.block(widget.target);
                return '${widget.firstName} is blocked. They won\'t be told.';
              }, SafetyOutcome.blocked),
            ),
            _Step.leave => _confirm(
              context,
              title: 'Leave this chat quietly?',
              body:
                  'The chat closes for both of you. ${widget.firstName} isn\'t notified and won\'t see a reason.',
              action: 'Leave quietly',
              onConfirm: () => _run((safety) async {
                await safety.leaveQuietly(widget.connectionId!);
                return 'You left the chat. ${widget.firstName} won\'t be told.';
              }, SafetyOutcome.left),
            ),
          },
        ),
      ),
    );
  }

  List<Widget> _menu(BuildContext context) => [
    Text('Safety', style: context.type.titleLarge),
    const SizedBox(height: OdSpace.x1),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.flag_rounded),
      title: const Text('Report'),
      subtitle: const Text('Tell our safety team what happened'),
      onTap: () => _go(_Step.report),
    ),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.block_rounded),
      title: const Text('Block'),
      subtitle: const Text('Stop seeing each other'),
      onTap: () => _go(_Step.block),
    ),
    if (widget.connectionId != null)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.logout_rounded),
        title: const Text('Leave quietly'),
        subtitle: const Text('They won\'t be told'),
        onTap: () => _go(_Step.leave),
      ),
  ];

  List<Widget> _report(BuildContext context) {
    final c = context.od;
    return [
      Text('What happened?', style: context.type.titleLarge),
      const SizedBox(height: OdSpace.x0_5),
      Text(
        '${widget.firstName} won\'t know you reported this.',
        style: context.type.bodyMedium,
      ),
      const SizedBox(height: OdSpace.x1),
      for (final category in ReportCategory.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(category.label, style: context.type.bodyLarge),
          trailing: Icon(
            _category == category
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: _category == category ? c.brand : c.textTertiary,
          ),
          selected: _category == category,
          onTap: _busy ? null : () => setState(() => _category = category),
        ),
      const SizedBox(height: OdSpace.x1),
      TextField(
        controller: _details,
        enabled: !_busy,
        minLines: 1,
        maxLines: 4,
        maxLength: ApiSafety.maxDetails,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Anything else we should know? (optional)',
          counterText: '',
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Also block ${widget.firstName}'),
        value: _alsoBlock,
        onChanged: _busy ? null : (on) => setState(() => _alsoBlock = on),
      ),
      if (_error != null) _ErrorLine(_error!),
      const SizedBox(height: OdSpace.x1),
      OdButton(
        label: 'Send report',
        expand: true,
        loading: _busy,
        onPressed: _category == null
            ? null
            : () => _run(
                (safety) => safety.report(
                  widget.target,
                  _category!,
                  details: _details.text,
                  alsoBlock: _alsoBlock,
                ),
                _alsoBlock ? SafetyOutcome.blocked : SafetyOutcome.reported,
              ),
      ),
      Center(
        child: OdButton(
          label: 'Back',
          variant: OdButtonVariant.ghost,
          onPressed: _busy ? null : () => _go(_Step.menu),
        ),
      ),
    ];
  }

  List<Widget> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required VoidCallback onConfirm,
  }) => [
    Text(title, style: context.type.titleLarge),
    const SizedBox(height: OdSpace.x1),
    Text(body, style: context.type.bodyLarge),
    if (_error != null) _ErrorLine(_error!),
    const SizedBox(height: OdSpace.x3),
    OdButton(
      label: action,
      expand: true,
      variant: OdButtonVariant.danger,
      loading: _busy,
      onPressed: onConfirm,
    ),
    Center(
      child: OdButton(
        label: 'Not now',
        variant: OdButtonVariant.ghost,
        onPressed: _busy ? null : () => _go(_Step.menu),
      ),
    ),
  ];
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: OdSpace.x1),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: context.type.bodyMedium?.copyWith(color: context.od.danger),
      ),
    ),
  );
}

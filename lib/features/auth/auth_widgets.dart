import 'package:flutter/material.dart';

import '../../core/network/api_error.dart';
import '../../design_system/design_system.dart';

/// The shared frame for every sign-in step: a short title, one line on why we ask, the inputs, and a single
/// primary action pinned above the keyboard. One decision per screen keeps the flow fast and calm.
class AuthStepScaffold extends StatelessWidget {
  const AuthStepScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.action,
    this.step,
    this.steps = 3,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget action;
  final int? step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Scaffold(
      appBar: AppBar(
        title: step == null
            ? null
            : Semantics(
                label: 'Step $step of $steps',
                child: ExcludeSemantics(
                  child: _StepBar(step: step!, steps: steps),
                ),
              ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  OdSpace.gutter,
                  OdSpace.x2,
                  OdSpace.gutter,
                  OdSpace.x2,
                ),
                children: [
                  Text(title, style: context.type.headlineSmall),
                  const SizedBox(height: OdSpace.x1),
                  Text(
                    subtitle,
                    style: context.type.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: OdSpace.x3),
                  ...children,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OdSpace.gutter,
                OdSpace.x1,
                OdSpace.gutter,
                OdSpace.x2,
              ),
              child: action,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.steps});

  final int step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= steps; i++)
          AnimatedContainer(
            duration: OdMotion.of(context, OdMotion.standard),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == step ? 28 : 12,
            height: 6,
            decoration: BoxDecoration(
              color: i <= step ? c.brand : c.outline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// An inline, polite error line (announced to screen readers) instead of a dialog that blocks the flow.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: OdMotion.of(context, OdMotion.quick),
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: ValueKey(message),
              padding: const EdgeInsets.only(top: OdSpace.x1_5),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: context.od.danger,
                    ),
                    const SizedBox(width: OdSpace.x1),
                    Expanded(
                      child: Text(
                        message!,
                        style: context.type.bodyMedium?.copyWith(
                          color: context.od.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Human wording for errors: the server's detail when it has one, a calm generic line otherwise.
String authMessage(Object error) => switch (error) {
  ApiError(code: 'NETWORK') =>
    'You seem to be offline. Check your connection and try again.',
  ApiError(:final detail) when detail.isNotEmpty => detail,
  _ => 'Something went wrong. Please try again.',
};

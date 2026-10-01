import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../design_system/design_system.dart';
import 'auth_widgets.dart';

/// Runs the liveness vendor's face check and returns its session token, or null if the person backed out.
/// Production plugs in the vendor SDK; development uses the backend's dev verifier, which accepts `dev-pass`.
abstract interface class LivenessCheck {
  Future<String?> run(BuildContext context);
}

class DevLivenessCheck implements LivenessCheck {
  const DevLivenessCheck();

  @override
  Future<String?> run(BuildContext context) async => 'dev-pass';
}

final livenessCheckProvider = Provider<LivenessCheck>(
  (ref) => const DevLivenessCheck(),
);

/// Asked for at the first contact action, not at the door (progressive verification): by then the person
/// knows why it matters. The copy says exactly what's kept and what isn't.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await ref.read(livenessCheckProvider).run(context);
      if (token == null) return;
      await ref.read(authControllerProvider.notifier).verifyLiveness(token);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return AuthStepScaffold(
      title: 'Show you\'re you',
      subtitle: 'A 10-second face check keeps OneDay free of fake profiles. Everyone you meet has done it too.',
      action: OdButton(
        label: 'Start face check',
        icon: Icons.face_retouching_natural_rounded,
        expand: true,
        loading: _busy,
        onPressed: _busy ? null : _start,
      ),
      children: [
        for (final (icon, text) in const [
          (
            Icons.videocam_off_rounded,
            'Our verification partner runs the check. OneDay gets only the result, never your video.',
          ),
          (
            Icons.verified_rounded,
            'You get a verified badge, and can send signals and chat.',
          ),
          (
            Icons.visibility_off_rounded,
            'Nobody else ever sees the check. Your profile shows only the badge.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: OdSpace.x2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: c.safety),
                const SizedBox(width: OdSpace.x1_5),
                Expanded(child: Text(text, style: context.type.bodyLarge)),
              ],
            ),
          ),
        AuthErrorText(_error),
      ],
    );
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../design_system/design_system.dart';
import 'auth_widgets.dart';

/// How the account is being created: a verified phone code, or an email and password.
class AboutYouArgs {
  const AboutYouArgs.phone({
    required String this.phone,
    required String this.challengeId,
    required String this.code,
  }) : email = null,
       password = null;

  const AboutYouArgs.email({
    required String this.email,
    required String this.password,
  }) : phone = null,
       challengeId = null,
       code = null;

  final String? phone;
  final String? challengeId;
  final String? code;
  final String? email;
  final String? password;
}

/// The only three things signup needs. Each one says why it's asked, and consent is a real, unticked choice.
class AboutYouScreen extends ConsumerStatefulWidget {
  const AboutYouScreen({super.key, required this.args, this.today});

  final AboutYouArgs args;

  /// Tests pin the date so the 18+ boundary is deterministic.
  final DateTime? today;

  @override
  ConsumerState<AboutYouScreen> createState() => _AboutYouScreenState();
}

class _AboutYouScreenState extends ConsumerState<AboutYouScreen> {
  final _name = TextEditingController();
  DateTime? _dob;
  bool _consent = false;
  bool _busy = false;
  String? _error;

  DateTime get _today => widget.today ?? DateTime.now();

  DateTime get _eighteenYearsAgo =>
      DateTime(_today.year - 18, _today.month, _today.day);

  bool get _adult => _dob != null && !_dob!.isAfter(_eighteenYearsAgo);

  bool get _ready =>
      _name.text.trim().isNotEmpty && _adult && _consent && !_busy;

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(_today.year - 24, 1, 1),
      firstDate: DateTime(_today.year - 100),
      lastDate: _today,
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Your date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final details = SignupDetails(displayName: _name.text, dateOfBirth: _dob!);
    final auth = ref.read(authControllerProvider.notifier);
    final a = widget.args;
    try {
      if (a.email != null) {
        await auth.registerWithEmail(
          email: a.email!,
          password: a.password!,
          details: details,
        );
      } else {
        await auth.verifyOtp(
          challengeId: a.challengeId!,
          phone: a.phone!,
          code: a.code!,
          details: details,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final dobLabel = _dob == null
        ? 'Date of birth'
        : MaterialLocalizations.of(context).formatMediumDate(_dob!);
    return AuthStepScaffold(
      step: 3,
      title: 'A little about you',
      subtitle: 'People see your first name and age. Never your birthday, number or email.',
      action: OdButton(
        label: 'Start OneDay',
        expand: true,
        loading: _busy,
        onPressed: _ready ? _submit : null,
      ),
      children: [
        TextField(
          key: const Key('name-field'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.givenName],
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'First name',
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: OdSpace.x2),
        OdPressable(
          onTap: _pickDob,
          semanticLabel: _dob == null
              ? 'Choose your date of birth'
              : 'Date of birth, $dobLabel. Change',
          child: OdCard(
            padding: const EdgeInsets.all(OdSpace.x2),
            child: Row(
              children: [
                Icon(Icons.cake_outlined, color: c.textSecondary),
                const SizedBox(width: OdSpace.x1_5),
                Expanded(
                  child: Text(dobLabel, style: context.type.titleMedium),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
          ),
        ),
        if (_dob != null && !_adult)
          const AuthErrorText('OneDay is only for adults 18 and over.'),
        const SizedBox(height: OdSpace.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: const Key('consent'),
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: OdSpace.x1_5),
                child: Text.rich(
                  TextSpan(
                    style: context.type.bodyMedium,
                    children: [
                      const TextSpan(text: 'I\'ve read the '),
                      TextSpan(
                        text: 'privacy notice',
                        style: TextStyle(
                          color: c.brand,
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => _showNotice(context),
                      ),
                      const TextSpan(
                        text:
                            ' and agree to OneDay using my approximate area to show me people nearby. '
                            'I can withdraw this any time in Settings.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        AuthErrorText(_error),
      ],
    );
  }

  void _showNotice(BuildContext context) => showOdSheet<void>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Privacy, in short', style: context.type.titleLarge),
        const SizedBox(height: OdSpace.x1_5),
        for (final line in const [
          'We use your approximate area, never your exact location, and only while the app is open.',
          'Moments disappear after a day unless you save them to your own Gallery.',
          'We don\'t sell your data or show you ads based on it.',
          'You can download or delete everything from Settings at any time.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: OdSpace.x1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(line, style: context.type.bodyMedium)),
              ],
            ),
          ),
      ],
    ),
  );
}

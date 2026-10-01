import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../design_system/design_system.dart';
import 'auth_widgets.dart';
import 'otp_screen.dart';

typedef Country = ({String flag, String name, String dial, int digits});

/// India first; the rest cover the largest diaspora markets. The server normalises to E.164 either way.
const countries = <Country>[
  (flag: '🇮🇳', name: 'India', dial: '+91', digits: 10),
  (flag: '🇺🇸', name: 'United States', dial: '+1', digits: 10),
  (flag: '🇬🇧', name: 'United Kingdom', dial: '+44', digits: 10),
  (flag: '🇦🇪', name: 'United Arab Emirates', dial: '+971', digits: 9),
  (flag: '🇸🇬', name: 'Singapore', dial: '+65', digits: 8),
  (flag: '🇨🇦', name: 'Canada', dial: '+1', digits: 10),
  (flag: '🇦🇺', name: 'Australia', dial: '+61', digits: 9),
];

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _number = TextEditingController();
  Country _country = countries.first;
  bool _busy = false;
  String? _error;

  String get _digits => _number.text.replaceAll(RegExp(r'\D'), '');

  bool get _valid =>
      _digits.length == _country.digits &&
      (_country.dial != '+91' || RegExp(r'^[6-9]').hasMatch(_digits));

  String get _e164 => '${_country.dial}$_digits';

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challengeId = await ref
          .read(authControllerProvider.notifier)
          .requestOtp(_e164);
      if (!mounted) return;
      context.push(
        '/auth/otp',
        extra: OtpArgs(phone: _e164, challengeId: challengeId),
      );
    } catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCountry() async {
    final picked = await showOdSheet<Country>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in countries)
            ListTile(
              leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
              title: Text(c.name),
              trailing: Text(c.dial, style: context.type.labelLarge),
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _country = picked);
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthStepScaffold(
      step: 1,
      title: 'What\'s your number?',
      subtitle: 'We\'ll text you a 6-digit code. Your number is never shown to anyone.',
      action: OdButton(
        label: 'Send code',
        expand: true,
        loading: _busy,
        onPressed: _valid && !_busy ? _send : null,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OdPressable(
              onTap: _pickCountry,
              semanticLabel: 'Country code ${_country.name} ${_country.dial}',
              child: OdCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: OdSpace.x1_5,
                  vertical: OdSpace.x2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_country.flag),
                    const SizedBox(width: OdSpace.x0_5),
                    Text(_country.dial, style: context.type.titleMedium),
                    const Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(width: OdSpace.x1),
            Expanded(
              child: TextField(
                key: const Key('phone-field'),
                controller: _number,
                autofocus: true,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_country.digits),
                ],
                style: context.type.titleLarge,
                decoration: const InputDecoration(hintText: 'Mobile number'),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _valid && !_busy ? _send() : null,
              ),
            ),
          ],
        ),
        AuthErrorText(_error),
      ],
    );
  }
}

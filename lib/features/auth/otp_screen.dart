import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/network/api_error.dart';
import '../../design_system/design_system.dart';
import 'about_you_screen.dart';
import 'auth_widgets.dart';

/// `+919876543210` → `+91 98765 43210`; other numbers are shown as entered.
String readablePhone(String e164) => e164.startsWith('+91') && e164.length == 13
    ? '+91 ${e164.substring(3, 8)} ${e164.substring(8)}'
    : e164;

class OtpArgs {
  const OtpArgs({required this.phone, required this.challengeId});

  final String phone;
  final String challengeId;
}

/// Six boxes over one real text field, so SMS autofill, paste and screen readers all just work. The code is
/// submitted the moment the sixth digit lands: no extra button press at the most impatient moment.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args});

  final OtpArgs args;

  static const resendAfter = Duration(seconds: 30);

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late String _challengeId = widget.args.challengeId;
  bool _busy = false;
  String? _error;
  int _wait = OtpScreen.resendAfter.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = OtpScreen.resendAfter.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (_busy || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyOtp(
            challengeId: _challengeId,
            phone: widget.args.phone,
            code: _code.text,
          );
      // The router redirect takes it from here.
    } on SignupDetailsRequired {
      if (!mounted) return;
      context.push(
        '/auth/about',
        extra: AboutYouArgs.phone(
          phone: widget.args.phone,
          challengeId: _challengeId,
          code: _code.text,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _code.clear();
      setState(
        () => _error = e is ApiError && e.code == 'OTP_EXPIRED'
            ? 'That code expired. Send a new one below.'
            : authMessage(e),
      );
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      _challengeId = await ref
          .read(authControllerProvider.notifier)
          .requestOtp(widget.args.phone);
      _code.clear();
      _startTimer();
    } catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return AuthStepScaffold(
      step: 2,
      title: 'Enter the code',
      subtitle:
          'Sent to ${readablePhone(widget.args.phone)}. It expires in 5 minutes.',
      action: _wait > 0
          ? Text(
              'Resend code in 0:${_wait.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: context.type.labelLarge?.copyWith(color: c.textTertiary),
            )
          : OdButton(
              label: 'Send a new code',
              variant: OdButtonVariant.ghost,
              expand: true,
              onPressed: _resend,
            ),
      children: [
        SizedBox(
          height: _Box.heightFor(context),
          child: Stack(
            children: [
              // The real field: invisible, but focusable, autofillable and readable by assistive tech.
              Opacity(
                opacity: 0,
                child: TextField(
                  key: const Key('otp-field'),
                  controller: _code,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (v) {
                    setState(() => _error = null);
                    if (v.length == 6) _verify();
                  },
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  onTap: _focus.requestFocus,
                  child: ExcludeSemantics(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_code, _focus]),
                      builder: (context, _) => Row(
                        children: [
                          for (var i = 0; i < 6; i++) ...[
                            if (i > 0)
                              SizedBox(width: i == 3 ? OdSpace.x2 : OdSpace.x1),
                            Expanded(
                              child: _Box(
                                digit: i < _code.text.length
                                    ? _code.text[i]
                                    : null,
                                active:
                                    _focus.hasFocus && i == _code.text.length,
                                error: _error != null,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: OdSpace.x2),
          const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ],
        AuthErrorText(_error),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.digit, required this.active, required this.error});

  final String? digit;
  final bool active;
  final bool error;

  /// Grows with the text size so a large digit never clips.
  static double heightFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(24) + 32;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return AnimatedContainer(
      duration: OdMotion.of(context, OdMotion.quick),
      height: heightFor(context),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(OdRadius.md),
        border: Border.all(
          width: active ? 2 : 1,
          color: error
              ? c.danger
              : active
              ? c.brand
              : c.outline,
        ),
      ),
      child: Text(digit ?? '', style: context.type.headlineSmall),
    );
  }
}
